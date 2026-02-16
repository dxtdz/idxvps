#!/usr/bin/env bash

### --- 1. CẤU HÌNH (8 CORE - 16G RAM - ĐƯỜNG DẪN /var) --- ###
DISK_FILE="/var/win10_idx.qcow2" 
ISO_FILE="/var/win10.iso"
ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195443"
REMOTE_PATH="gdrive:IDX_VM/win10_idx.qcow2"
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
        # Đảm bảo tên file sau khi tải về khớp với cấu hình DISK_FILE
        # (Sửa trường hợp rclone tải về giữ tên cũ win10_lite.qcow2)
        ACTUAL_DOWNLOAD=$(rclone lsf "$REMOTE_PATH")
        if [ "$ACTUAL_DOWNLOAD" != "win10_idx.qcow2" ]; then
            mv "/var/$ACTUAL_DOWNLOAD" "$DISK_FILE"
        fi
        touch "$FLAG_FILE"
    else
        echo "🆕 Không có backup trên Cloud. Chuyển sang chế độ cài đặt mới."
        rm -f "$FLAG_FILE"
        [ -f "$DISK_FILE" ] || qemu-img create -f qcow2 "$DISK_FILE" 64G
        [ -f "$ISO_FILE" ] || wget -O "$ISO_FILE" "$ISO_URL"
    fi
fi

### --- 3. KẾT NỐI (BORE) --- ###
bore local 5900 --to bore.pub > /tmp/bore.log 2>&1 &
sleep 8
VNC_ADDR=$(grep -oE 'bore.pub:[0-9]+' /tmp/bore.log | tail -n 1)

### --- 4. CHẾ ĐỘ BOOT --- ###
if [ ! -f "$FLAG_FILE" ]; then
    BOOT_ARGS="-cdrom $ISO_FILE -boot order=d"
    MODE="CÀI ĐẶT (ISO)"
else
    BOOT_ARGS="-boot order=c"
    MODE="SỬ DỤNG (DISK)"
fi

### --- 5. KHỞI CHẠY QEMU (TỐI ƯU GHI ĐĨA) --- ###
echo "------------------------------------------------"
echo "🚀 MÁY ẢO ĐANG CHẠY - CHẾ ĐỘ: $MODE"
echo "🖥️  VNC PUBLIC: $VNC_ADDR"
echo "🛑 GÕ 'xong' VÀ ENTER ĐỂ TẮT & BACKUP"
echo "------------------------------------------------"

qemu-system-x86_64 \
    -enable-kvm -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
    -smp "$CORES" -m "$RAM" -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2,cache=unsafe,aio=threads \
    $BOOT_ARGS \
    -netdev user,id=net0,hostfwd=tcp::3389-:3389 -device e1000,netdev=net0 \
    -vnc :0 -usb -device usb-tablet &

QEMU_PID=$!

### --- 6. LẤY CHAT ID & GỬI TELEGRAM --- ###
TG_CHAT_ID=$(curl -s "https://api.telegram.org/bot$TG_TOKEN/getUpdates" | jq -r '.result[-1].message.chat.id // .result[-1].callback_query.message.chat.id')
if [ ! -z "$VNC_ADDR" ] && [ "$TG_CHAT_ID" != "null" ]; then
    MSG="🖥️ Windows Ready!%0A🔗 VNC: \`$VNC_ADDR\`%0A🚀 Chế độ: $MODE%0A🛑 Gõ 'xong' để Backup."
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

# Tùy chọn: Xóa file cục bộ để tiết kiệm bộ nhớ (Muốn giữ file thì thêm dấu # vào dòng dưới)
# rm -f "$DISK_FILE"

echo "✅ HOÀN TẤT!"
