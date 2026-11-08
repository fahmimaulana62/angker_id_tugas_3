import 'package:flutter/foundation.dart';

import '../models/product_model.dart';
import '../models/sort_option.dart';
import '../services/api_service_products.dart';

/// State utama produk: daftar Beranda, detail, dan operasi CRUD.
/// Semua perubahan (tambah/edit/hapus) tersimpan permanen di backend (MySQL),
/// jadi data di aplikasi selalu mengikuti data di server.
class ProductProvider extends ChangeNotifier {
  ProductProvider(this._api);

  final ApiServiceProducts _api;
  static const int pageSize = 20;

  // ---- State Beranda ----
  List<Product> _products = [];
  int _total = 0;
  int _serverSkip = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _loadMoreError;
  String? _selectedCategory;
  SortOption _sort = SortOption.none;
  int _requestId = 0;
  bool _initialized = false;

  // ---- Cache detail & penanda produk yang sudah dihapus ----
  final Map<int, Product> _detailCache = {};
  final Set<int> _deletedIds = {};

  List<Product> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  String? get loadMoreError => _loadMoreError;
  String? get selectedCategory => _selectedCategory;
  SortOption get sort => _sort;
  bool get initialized => _initialized;

  /// Masih ada halaman berikutnya? (kategori dimuat sekaligus, tanpa pagination)
  bool get hasMore => _selectedCategory == null && _serverSkip < _total;

  /// Jumlah produk yang ditampilkan di "N produk tersedia".
    int get displayTotal => _selectedCategory != null ? _products.length : _total;

  /// Produk dengan diskon terbesar dari data yang sudah dimuat (untuk banner promo).
  Product? get bestDeal {
    if (_products.isEmpty) return null;
    return _products
        .reduce((a, b) => a.discountPercentage >= b.discountPercentage ? a : b);
  }

  // =========================================================================
  // Daftar produk Beranda
  // =========================================================================

  /// Muat halaman pertama sesuai filter kategori & urutan yang aktif.
  Future<void> fetchInitial() async {
    final reqId = ++_requestId;
    _isLoading = true;
    _error = null;
    _loadMoreError = null;
    notifyListeners();

    try {
      final ProductsResponse res;
      final category = _selectedCategory;
      if (category != null) {
        // GET /products/category/{slug}
        res = await _api.getProductsByCategory(
          category,
          sortBy: _sort.sortBy,
          order: _sort.order,
          select: kHomeSelect,
        );
      } else if (_sort == SortOption.none) {
        // GET /products?limit=&skip=&select=
        res = await _api.getProductsPaginated(
            limit: pageSize, skip: 0, select: kHomeSelect);
      } else {
        // GET /products?sortBy=&order=&limit=&skip=&select=
        res = await _api.sortProducts(
          _sort.sortBy!,
          _sort.order!,
          limit: pageSize,
          skip: 0,
          select: kHomeSelect,
        );
      }
      if (reqId != _requestId) return;

      _total = res.total;
      _serverSkip = category != null ? res.total : res.products.length;
      _products = applyLocalChanges(
        res.products,
        includeLocal: (p) => category == null || p.category == category,
      );
      _initialized = true;
    } on ApiException catch (e) {
      if (reqId != _requestId) return;
      _error = e.message;
    } finally {
      if (reqId == _requestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Infinite scroll: muat halaman berikutnya memakai limit & skip.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !hasMore) return;
    final reqId = _requestId;
    _isLoadingMore = true;
    _loadMoreError = null;
    notifyListeners();

    try {
      final res = _sort == SortOption.none
          ? await _api.getProductsPaginated(
              limit: pageSize, skip: _serverSkip, select: kHomeSelect)
          : await _api.sortProducts(
              _sort.sortBy!,
              _sort.order!,
              limit: pageSize,
              skip: _serverSkip,
              select: kHomeSelect,
            );
      if (reqId != _requestId) return;

      _total = res.total;
      _serverSkip += res.products.length;
      if (res.products.isEmpty) _total = _serverSkip;
      final existing = _products.map((p) => p.id).toSet();
      _products = [
        ..._products,
        ...applyLocalChanges(res.products, includeLocal: (_) => false)
            .where((p) => !existing.contains(p.id)),
      ];
    } on ApiException catch (e) {
      if (reqId == _requestId) _loadMoreError = e.message;
    } finally {
      if (reqId == _requestId) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => fetchInitial();

  void setSort(SortOption option) {
    if (option == _sort) return;
    _sort = option;
    fetchInitial();
  }

  void filterByCategory(String? slug) {
    if (slug == _selectedCategory) return;
    _selectedCategory = slug;
    fetchInitial();
  }

  /// Produk per kategori untuk halaman kategori (GET /products/category/{slug}).
  Future<List<Product>> fetchCategoryProducts(
      String slug, SortOption sort) async {
    final res = await _api.getProductsByCategory(slug,
        sortBy: sort.sortBy, order: sort.order);
    return res.products;
  }

   /// Dulu menempelkan hasil CRUD simulasi ke data server. Sekarang server
  /// sudah menyimpan semua perubahan, jadi data server dipakai apa adanya.
  /// Fungsi tetap dipertahankan karena dipakai juga oleh kategori & search.
  List<Product> applyLocalChanges(
    List<Product> fromServer, {
    bool Function(Product p)? includeLocal,
  }) {
    return fromServer.where((p) => !_deletedIds.contains(p.id)).toList();
  }

  // =========================================================================
  // Detail produk
  // =========================================================================

    bool isDeleted(int id) => _deletedIds.contains(id);

  /// Data yang sudah ada di memori (untuk ditampilkan instan sebelum detail selesai dimuat).
  Product? peek(int id) {
    if (_detailCache.containsKey(id)) return _detailCache[id];
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Produk lengkap bila sudah pernah dimuat.
  Product? fullProduct(int id) => _detailCache[id];

  /// GET /products/{id}. Semua produk, termasuk produk baru, diambil dari server.
  Future<Product> getProductDetail(int id, {bool forceRefresh = false}) async {
    if (!forceRefresh && _detailCache.containsKey(id)) return _detailCache[id]!;
    final product = await _api.getProduct(id);
    _detailCache[id] = product;
    return product;
  }

  // =========================================================================
  // CRUD (tersimpan permanen di MySQL lewat backend)
  // =========================================================================

  /// POST /products/add → id dibuat oleh database.
  Future<Product> addProduct(Product draft) async {
    final saved = await _api.addProduct(
      draft
          .copyWith(availabilityStatus: Product.statusFor(draft.stock))
          .toUpdateJson(),
    );
    _detailCache[saved.id] = saved;
    _total += 1;
    if (_selectedCategory == null || _selectedCategory == saved.category) {
      _products = [saved, ..._products];
    }
    notifyListeners();
    return saved;
  }

  /// PUT /products/{id}
  Future<Product> updateProduct(Product updated) async {
    final draft =
        updated.copyWith(availabilityStatus: Product.statusFor(updated.stock));
    final saved = await _api.updateProduct(draft.id, draft.toUpdateJson());
    _store(saved);
    return saved;
  }

  /// PATCH /products/{id} (update cepat stok/harga)
  Future<Product> patchProduct(int id, {int? stock, double? price}) async {
    final data = <String, dynamic>{
      if (stock != null) 'stock': stock,
      if (stock != null) 'availabilityStatus': Product.statusFor(stock),
      if (price != null) 'price': price,
    };
    final saved = await _api.patchProduct(id, data);
    _store(saved);
    return saved;
  }

  /// DELETE /products/{id}. Mengembalikan nilai deletedOn dari server.
  Future<String> deleteProduct(int id) async {
    final res = await _api.deleteProduct(id);
    _deletedIds.add(id);
    _detailCache.remove(id);
    _products = _products.where((p) => p.id != id).toList();
    if (_total > 0) _total -= 1;
    notifyListeners();
    return res.deletedOn ?? DateTime.now().toIso8601String();
  }

  /// Simpan versi terbaru dari server ke cache & daftar Beranda.
  void _store(Product p) {
    _detailCache[p.id] = p;
    _products = _products.map((e) => e.id == p.id ? p : e).toList();
    notifyListeners();
  }
}
