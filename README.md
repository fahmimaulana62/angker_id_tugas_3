# Angker.id 👻

## Identitas
- Nama: Fahmi Maulana Sitakar
- NIM: 230102042
- Kelas: IF24A
- Mata kuliah: Pemrograman Perangkat Bergerak

## Backend
Aplikasi memakai backend dari repo contoh dosen:
https://github.com/vpratama/pcc_sample_php_mysql_services

Backend dijalankan dengan Docker Compose dan terdiri dari:
- **Caddy** (web server, port `8080`) → pintu masuk API
- **PHP-FPM** → menjalankan kode API
- **MySQL 8.4** → menyimpan data produk (data tetap ada walaupun container dimatikan)
- **phpMyAdmin** (port `8081`) → melihat isi database

Data awal (194 produk) diisi dari DummyJSON lewat script seed. Setelah itu, semua perubahan dari aplikasi tersimpan di MySQL.

## Fitur
| Fitur | Endpoint Backend |
|---|---|
| Halaman depan berisi seluruh produk + infinite scroll | `GET /products?limit=&skip=&select=` |
| Urutkan produk (rating, harga, nama) | `GET /products?sortBy=&order=` |
| Detail produk | `GET /products/{id}` |
| Search fungsional (debounce + riwayat) | `GET /products?q=` |
| Tab kategori | `GET /products/categories` |
| Chip filter kategori di Beranda & dropdown form | `GET /products/category-list` |
| Produk per kategori | `GET /products/category/{slug}` |
| Tambah produk | `POST /products/add` |
| Edit produk | `PUT /products/{id}` |
| Update cepat stok & harga | `PATCH /products/{id}` |
| Hapus produk | `DELETE /products/{id}` |

Fitur tambahan:
- Splash screen **Angker.id** dengan animasi huruf berjatuhan dan memantul
- Wishlist (tersimpan permanen, ada tombol undo)
- Keranjang dengan pengatur jumlah yang dibatasi stok, voucher (`ANGKERHEMAT`, `HANTULUCU`), dan ringkasan pembayaran
- Rating bintang dan distribusi bintang
- Pull to refresh, shimmer loading, empty state, dan error state dengan tombol coba lagi
- Transisi Hero kartu → detail, animasi kartu bertahap, bottom navigation dengan pill yang bergeser

> Catatan: data seed dari backend tidak menyertakan ulasan dan galeri gambar, sehingga bagian ulasan dan galeri di halaman detail kosong (hanya thumbnail yang tampil).

## Cara Menjalankan

### 1. Backend (Docker)
Butuh Docker Desktop. Pastikan port `3306` dan `8080` tidak dipakai aplikasi lain (misalnya MySQL dari XAMPP).

```bash
git clone https://github.com/vpratama/pcc_sample_php_mysql_services.git
cd pcc_sample_php_mysql_services
copy .env.example .env          # Windows (Linux/Mac: cp .env.example .env)
docker compose up -d --build
docker compose exec php php /var/www/html/seed.php
```

Cek di browser: `http://localhost:8080/products`

### 2. Aplikasi Flutter
Butuh Flutter 3.27 atau lebih baru.

1. Cari IP laptop dengan `ipconfig` (lihat **IPv4 Address**).
2. Ubah `baseUrl` di `lib/services/api_service_products.dart`:
   ```dart
   baseUrl: 'http://<IP-laptop>:8080',
   ```
3. Pastikan HP dan laptop terhubung ke **WiFi yang sama**.
4. Jalankan:
   ```bash
   flutter pub get
   flutter run
   ```

## Perubahan dari Versi Sebelumnya (DummyJSON)
- **`lib/services/api_service_products.dart`**: `baseUrl` diarahkan ke backend Docker, dan alamat search diubah dari `/products/search` menjadi `/products` dengan parameter `q`.
- **`lib/providers/product_provider.dart`**: logika simulasi dihapus (`_localAdded`, `_overrides`, `_nextLocalId`, dan pengecekan `id > 194`). Sekarang setiap tambah, edit, update stok, dan hapus **selalu memanggil API**, dan aplikasi memakai data yang dibalas server.
- **`android/app/src/main/AndroidManifest.xml`**: ditambahkan `android:usesCleartextTraffic="true"` karena backend lokal memakai `http://`.

## Perbaikan pada Backend Dosen
Saat pengujian, ditemukan beberapa hal di `htdocs/controller/ProductController.php` (fungsi `index`):

1. **Bug search (error 500, `SQLSTATE[HY093]: Invalid parameter number`)**
   Placeholder `:search` dipakai 3 kali (title, description, brand), tetapi nilainya hanya diisi 1 kali. Diperbaiki dengan memberi nama berbeda:
   ```php
   $where[] = '(title LIKE :search1 OR description LIKE :search2 OR brand LIKE :search3)';
   $parameters[':search1'] = '%' . $search . '%';
   $parameters[':search2'] = '%' . $search . '%';
   $parameters[':search3'] = '%' . $search . '%';
   ```
2. **Route `/products/search` tidak tersedia** di router (`htdocs/routes/api.php`), walaupun tercantum di README backend. Aplikasi memakai `GET /products?q=`.
3. **Urutan hasil search berdasarkan relevansi**: kalau pengguna tidak memilih urutan, produk yang kategorinya cocok tampil paling atas, lalu yang judulnya cocok, lalu sisanya.
   ```php
   $orderSql = " ORDER BY {$sortBy} {$order}";
   if ($search !== '' && !isset($_GET['sortBy'])) {
       $orderSql = ' ORDER BY CASE
           WHEN category LIKE :rank1 THEN 0
           WHEN title LIKE :rank2 THEN 1
           ELSE 2 END, id ASC';
   }
   ```
   Parameter `:rank1` dan `:rank2` diisi terpisah (hanya untuk query daftar produk), supaya query `COUNT(*)` tidak kembali terkena error `HY093`.

## Tech Stack
**Aplikasi:** Flutter · Dio · Provider · GoRouter · CachedNetworkImage · SharedPreferences · Shimmer · Google Fonts
**Backend:** PHP 8.3 (FPM) · MySQL 8.4 · Caddy · Docker Compose

## Struktur Kode
```
lib/
├── main.dart, app.dart          # entry point + MultiProvider
├── core/                        # tema, router (go_router), formatter
├── models/                      # Product, Review, Dimensions, Meta, ProductCategory, CartItem
├── services/                    # ApiServiceProducts (semua endpoint ke backend) + penyimpanan lokal
├── providers/                   # Product, Category, Search, Wishlist, Cart
├── screens/                     # splash, home, search, detail, category, wishlist, cart, form
└── widgets/                     # kartu produk, stepper, shimmer, state view, dll
```


## Palet Warna
`#F9B2D7` · `#CFECF3` · `#DAF9DE` · `#F6FFDC` (aksen: `#993D71`, `#E37AB2`, `#6FAFC2`, `#5DAA6E`)

## Catatan Penggunaan AI
[bagian perbaikan debugging yang dibantu AI claude, sisanya saya kerjakan sendiri dengan instruksi dari claude]          