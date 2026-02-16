#!/usr/bin/env bash

### --- 1. CẤU HÌNH (8 CORE - 16G RAM - ĐƯỜNG DẪN /var) --- ###
DISK_FILE="/var/debian11_idx.qcow2" 
ISO_FILE="/var/debian11.iso"
# Debian 11 netinstall ISO
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.6.0-amd64-netinst.iso"
REMOTE_PATH="gdrive:IDX_VM/debian11_idx.qcow2"
TG_TOKEN="7690008899:AAGRoIPhk104PFAhhP4rAIcTZc_uvDpCUZQ"
FLAG_FILE="$HOME/installed.flag"
RAM="16G" 
CORES="8"

# Dọn dẹp tiến trình cũ
pkill -9 -f qemu || true
pkill -9 -f rclone || true
pkill -9 -f bore || true
sleep 2

### --- 2. KIỂM TRA DỮ LIỆU & TỰ ĐỘNG KHÔI PHỤC --- ###
if [ ! -f "$DISK_FILE" ]; then
    echo "⚠️  Cảnh báo: Không tìm thấy file ổ đĩa tại $DISK_FILE"
    echo "🔍 Đang kiểm tra bản backup trên Cloud để khôi phục..."
    
    # Kiểm tra xem có bản backup trên Drive không
    if rclone lsf "$REMOTE_PATH" >/dev/null 2>&1; then
        echo "📥 Đã thấy bản backup! Đang tải về /var (Vui lòng đợi)..."
        rclone copy "$REMOTE_PATH" "/var/" -P
        ACTUAL_DOWNLOAD=$(rclone lsf "$REMOTE_PATH")
        if [ "$ACTUAL_DOWNLOAD" != "debian11_idx.qcow2" ]; then
            mv "/var/$ACTUAL_DOWNLOAD" "$DISK_FILE"
        fi
        touch "$FLAG_FILE"
    else
        echo "🆕 Không có backup trên Cloud. Chuyển sang chế độ cài đặt mới."
        rm -f "$FLAG_FILE"
        [ -f "$DISK_FILE" ] || qemu-img create -f qcow2 "$DISK_FILE" 20G
        [ -f "$ISO_FILE" ] || wget -O "$ISO_FILE" "$ISO_URL"
    fi
fi

### --- 3. TẠO TUNNEL CHO RDP (CỔNG 3389) --- ###
# Sử dụng bore để tunnel cổng RDP (3389) thay vì VNC (5900)
bore local 3389 --to bore.pub > /tmp/bore.log 2>&1 &
sleep 8
RDP_ADDR=$(grep -oE 'bore.pub:[0-9]+' /tmp/bore.log | tail -n 1)

### --- 4. CHẾ ĐỘ BOOT --- ###
if [ ! -f "$FLAG_FILE" ]; then
    # Lần đầu cài đặt - cần VNC để cài OS
    echo "🔧 Lần đầu cài đặt - Dùng VNC để cài Debian 11"
    echo "📝 Sau khi cài xong, nhớ chạy lệnh sau trong VM để bật RDP:"
    echo "   sudo apt update && sudo apt install -y xfce4 xfce4-goodies xrdp"
    echo "   sudo systemctl enable xrdp && sudo systemctl start xrdp"
    BOOT_ARGS="-cdrom $ISO_FILE -boot order=d -vnc :0"
    MODE="CÀI ĐẶT DEBIAN 11 (DÙNG VNC)"
    CONNECT_INFO="VNC: $RDP_ADDR (dùng VNC viewer)"
else
    # Đã cài xong - chạy bình thường với RDP
    BOOT_ARGS="-boot order=c -vnc :0"  # Vẫn giữ VNC phòng khi cần debug
    MODE="SỬ DỤNG DEBIAN 11 (DÙNG RDP)"
    CONNECT_INFO="RDP: $RDP_ADDR (dùng Remote Desktop)"
fi

### --- 5. KHỞI CHẠY QEMU VỚI PORT RDP ĐƯỢC FORWARD --- ###
echo "------------------------------------------------"
echo "🐧 MÁY ẢO DEBIAN 11 ĐANG CHẠY"
echo "🔗 KẾT NỐI: $CONNECT_INFO"
echo "💡 Nếu dùng RDP: Mở Remote Desktop và nhập địa chỉ trên"
echo "🛑 GÕ 'xong' VÀ ENTER ĐỂ TẮT & BACKUP"
echo "------------------------------------------------"

qemu-system-x86_64 \
    -enable-kvm -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
    -smp "$CORES" -m "$RAM" -machine q35 \
    -drive file="$DISK_FILE",if=virtio,format=qcow2,cache=unsafe,aio=threads \
    $BOOT_ARGS \
    -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
    -device virtio-net,netdev=net0 \
    -usb -device usb-tablet &

QEMU_PID=$!

### --- 6. GỬI THÔNG BÁO QUA TELEGRAM --- ###
TG_CHAT_ID=$(curl -s "https://api.telegram.org/bot$TG_TOKEN/getUpdates" | jq -r '.result[-1].message.chat.id // .result[-1].callback_query.message.chat.id')
if [ ! -z "$RDP_ADDR" ] && [ "$TG_CHAT_ID" != "null" ]; then
    if [ ! -f "$FLAG_FILE" ]; then
        MSG="🐧 *Cài Debian 11 - Dùng VNC*%0A🔗 VNC: \`$RDP_ADDR\`%0A📝 Sau cài đặt: sudo apt install -y xfce4 xrdp"
    else
        MSG="🐧 *Debian 11 sẵn sàng*%0A🖥️ RDP: \`$RDP_ADDR\`%0A🔑 User: \`user\` | Pass: \`123\` (nếu dùng script tự động)"
    fi
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_CHAT_ID&text=$MSG&parse_mode=Markdown" > /dev/null
fi

### --- 7. ĐỢI LỆNH TẮT --- ###
while true; do
    read -rp "👉 Nhập 'xong' để dừng máy & backup: " input
    if [ "$input" == "xong" ]; then
        echo "🛑 Đang tắt máy ảo..."
        kill "$QEMU_PID" || pkill -f qemu-system-x86_64
        if [ ! -f "$FLAG_FILE" ]; then
            touch "$FLAG_FILE"
            rm -f "$ISO_FILE"
        fi
        break
    fi
done

### --- 8. BACKUP & DỌN DẸP --- ###
echo "📤 Đang đồng bộ bản mới nhất lên Drive..."
rclone copy "$DISK_FILE" "gdrive:IDX_VM/" -P

echo "✅ HOÀN TẤT!"
