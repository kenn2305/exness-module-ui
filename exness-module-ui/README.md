# Exness Module UI

Rootless tweak chỉnh giao diện trực tiếp trong Exness trên thiết bị jailbreak iOS 15–16, build cho `arm64` và `arm64e`.

## Tính năng

- Quét icon, nút và text đang hiển thị trong màn hình Exness.
- Di chuyển tương đối theo ngón tay; phóng to/thu nhỏ bằng pinch hoặc thanh Scale.
- Scale tối đa `50×`, giữ ảnh gốc khi nhập từ Photos để hạn chế mờ khi phóng lớn.
- Thêm ảnh, SF Symbol hoặc text mới; sửa nội dung text có sẵn.
- Ẩn, thay thế và liên kết icon tùy biến với hành động của nút gốc.
- Lưu layout riêng cho mỗi màn hình/tab và áp ngay khi cây giao diện thay đổi.
- Overlay nằm trong đúng scroll view để text/icon cuộn cùng nội dung; thành phần chức năng cố định không bị ép cuộn.
- Panel thao tác xuất hiện khi chạm vào phần tử đã Apply.
- Tự phân loại label, ảnh, tiêu đề nút và phần tử có hành động; editor hiển thị vai trò của mục đang chọn.
- Mỗi chỉnh sửa có chế độ `Follow` để bám phần tử/vùng cuộn hoặc chuyển sang `Fixed` để đứng yên trên màn hình.
- Tọa độ được lưu theo container thay vì chỉ theo toàn màn hình, tránh nhảy vị trí sau khi cuộn hoặc đổi tab rồi quay lại.

## Mở editor

Mở Exness rồi **nhấn giữ ba ngón tay ở bất kỳ vị trí nào khoảng 0,8 giây**. Cử chỉ không phụ thuộc `UITabBarController`, nên dùng được cả với giao diện React Native/SwiftUI được host bằng UIKit.

Nếu Exness có tab bar UIKit thật, màn hình đầu tiên là Module Designer để sắp xếp module. Nếu tab bar là thành phần tùy biến, tool mở thẳng Screen Editor.

## Tương thích quan trọng

Bundle được nghiên cứu là `com.exness.mobile`, executable `ExnessMobile`. Exness 4.96.1 khai báo iOS 15 nhưng gọi Swift runtime `_swift_getExtendedExistentialTypeMetadata`, chỉ có trong runtime mới hơn, nên bản đó crash trước khi tweak có thể hoạt động trên iOS 15. Cần dùng một bản Exness cũ hơn thực sự chạy được trên iOS 15 để kiểm thử/cài tool.

Tool chỉ chỉnh lớp giao diện. Nó không hook đăng nhập, mạng, giá, lệnh Buy/Sell, tài khoản hoặc dữ liệu giao dịch.

## Build

```sh
cd exness-module-ui
python3 scripts/validate_project.py
gmake clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

Gói `.deb` nằm trong `packages/`. GitHub Actions dùng macOS, Theos và SDK iOS để xác minh cả hai slice `arm64`/`arm64e`, sau đó có thể phát hành APT repository cho Sileo qua GitHub Pages.

## Cài qua Sileo

Sau khi workflow đã publish GitHub Pages:

1. Thêm URL repo GitHub Pages vào Sources của Sileo.
2. Refresh Sources.
3. Tìm `Exness Module UI`, cài và Respring.
4. Mở bản Exness tương thích iOS 15, nhấn giữ ba ngón để mở editor.

Không cài tool lên bản Exness 4.96.1 đang crash; tool không thể sửa lỗi Swift runtime xảy ra trước khi UI khởi động.
