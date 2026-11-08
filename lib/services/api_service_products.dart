import 'package:dio/dio.dart';

import '../models/category_model.dart';
import '../models/product_model.dart';

/// Field ringkas untuk grid Beranda (endpoint ?select=), supaya payload lebih ringan.
const String kHomeSelect =
    'id,title,price,discountPercentage,rating,stock,brand,category,thumbnail,availabilityStatus';

/// Exception dengan pesan Bahasa Indonesia yang siap ditampilkan ke user.
class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// Semua endpoint DummyJSON Products yang diwajibkan modul praktikum.
class ApiServiceProducts {
  ApiServiceProducts({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'http://192.168.1.4:8080',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Content-Type': 'application/json'},
            ));

  final Dio _dio;

  /// Endpoint 1, 4, 5:
  /// GET /products?limit=&skip=            (pagination)
  /// GET /products?limit=&skip=&select=    (field tertentu saja)
  /// GET /products?sortBy=&order=          (urutkan)
  Future<ProductsResponse> getAllProducts({
    int limit = 20,
    int skip = 0,
    String? select,
    String? sortBy,
    String? order,
  }) {
    return _guard(() async {
      final res = await _dio.get('/products', queryParameters: {
        'limit': limit,
        'skip': skip,
        if (select != null) 'select': select,
        if (sortBy != null) 'sortBy': sortBy,
        if (sortBy != null) 'order': order ?? 'asc',
      });
      return ProductsResponse.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 4: GET /products?limit=10&skip=10&select=title,price
  Future<ProductsResponse> getProductsPaginated(
          {int limit = 10, int skip = 0, String? select}) =>
      getAllProducts(limit: limit, skip: skip, select: select);

  /// Endpoint 5: GET /products?sortBy=title&order=asc
  Future<ProductsResponse> sortProducts(
    String sortBy,
    String order, {
    int limit = 20,
    int skip = 0,
    String? select,
  }) =>
      getAllProducts(
          limit: limit,
          skip: skip,
          select: select,
          sortBy: sortBy,
          order: order);

  /// Endpoint 2: GET /products/{id}
  Future<Product> getProduct(int id) {
    return _guard(() async {
      final res = await _dio.get('/products/$id');
      return Product.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 3: GET /products/search?q=phone
  Future<ProductsResponse> searchProducts(
    String query, {
    int limit = 0,
    CancelToken? cancelToken,
  }) {
    return _guard(() async {
      final res = await _dio.get(
        '/products',
        queryParameters: {'q': query, 'limit': limit},
        cancelToken: cancelToken,
      );
      return ProductsResponse.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 6: GET /products/categories
  Future<List<ProductCategory>> getCategories() {
    return _guard(() async {
      final res = await _dio.get('/products/categories');
      return (res.data as List)
          .whereType<Map<String, dynamic>>()
          .map(ProductCategory.fromJson)
          .toList();
    });
  }

  /// Endpoint 7: GET /products/category-list
  Future<List<String>> getCategoryList() {
    return _guard(() async {
      final res = await _dio.get('/products/category-list');
      return (res.data as List).map((e) => e.toString()).toList();
    });
  }

  /// Endpoint 8: GET /products/category/{slug}
  Future<ProductsResponse> getProductsByCategory(
    String slug, {
    String? sortBy,
    String? order,
    String? select,
  }) {
    return _guard(() async {
      final res = await _dio.get('/products/category/$slug', queryParameters: {
        'limit': 0,
        if (select != null) 'select': select,
        if (sortBy != null) 'sortBy': sortBy,
        if (sortBy != null) 'order': order ?? 'asc',
      });
      return ProductsResponse.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 9: POST /products/add (mock, server mengembalikan id 195)
  Future<Product> addProduct(Map<String, dynamic> data) {
    return _guard(() async {
      final res = await _dio.post('/products/add', data: data);
      return Product.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 10: PUT /products/{id} (update penuh, mock)
  Future<Product> updateProduct(int id, Map<String, dynamic> data) {
    return _guard(() async {
      final res = await _dio.put('/products/$id', data: data);
      return Product.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 11: PATCH /products/{id} (update sebagian, mock)
  Future<Product> patchProduct(int id, Map<String, dynamic> data) {
    return _guard(() async {
      final res = await _dio.patch('/products/$id', data: data);
      return Product.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Endpoint 12: DELETE /products/{id} (mock, mengembalikan isDeleted & deletedOn)
  Future<Product> deleteProduct(int id) {
    return _guard(() async {
      final res = await _dio.delete('/products/$id');
      return Product.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Mengubah semua error jaringan menjadi [ApiException] berbahasa Indonesia.
  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ApiException(_messageFor(e));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
          'Data dari server tidak bisa dibaca. Coba lagi ya.');
    }
  }

  String _messageFor(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server tidak merespons. Periksa koneksi lalu coba lagi.';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi internet.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 404) return 'Produk tidak ditemukan.';
        if (code >= 500) return 'Server sedang bermasalah ($code).';

        return 'Permintaan gagal (kode $code).';
      default:
        return 'Terjadi kesalahan jaringan. Coba lagi ya.';
    }
  }
}
