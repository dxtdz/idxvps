{ pkgs, ... }: {
  packages = with pkgs; [
    # Core packages để chạy máy ảo
    qemu_full      # Chạy máy ảo (qemu-system-x86_64)
    rclone         # Đồng bộ với Google Drive
    wget           # Tải ISO
    bore-cli       # Tạo tunnel public (bore local)
    util-linux     # Các lệnh hệ thống (pkill, kill)
    jq             # Parse JSON từ Telegram API
    curl           # Gọi Telegram API
    
    # === CÁC PACKAGE CẦN THÊM ===
    
    # 1. Cần cho pkill (thường có sẵn trong procps)
    procps         # Cung cấp pkill, kill
    
    # 2. Cần cho các lệnh network cơ bản
    netcat         # Kiểm tra kết nối (nếu cần debug)
    iproute2       # Các lệnh ip, ss (thay thế ifconfig)
    
    # 3. Cần cho việc tạo disk image (qemu-img đã có trong qemu_full)
    # qemu-img đã được bao gồm trong qemu_full
    
    # 4. Cần cho việc mount/nếu có thao tác với disk
    e2fsprogs      # Các lệnh filesystem (nếu cần)
    
    # 5. Cần cho việc nén/giải nén (nếu có)
    gzip           # Nén/giải nén
    unzip          # Giải nén zip
    
    # 6. Cần cho việc kiểm tra disk
    parted         # Quản lý partition
    gptfdisk       # Công cụ GPT (gdisk)
    
    # 7. Optional: Công cụ debug mạng
    tcpdump        # Bắt gói tin (nếu cần debug)
    bind           # Cung cấp dig, 
];

  idx.workspace.onStart = {
    setup-and-run = ''
      mkdir -p /home/user/windows-idx
      chmod +x run.sh
      bash run.sh
    '';
  };
