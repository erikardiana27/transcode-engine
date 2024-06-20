#!/bin/bash

# Fungsi untuk menambahkan tugas ke antrian Redis
add_to_redis_queue() {
    local input_file="$1"
    local output_folder="$2"
    local after_transcode_folder="$3"
    local watermark="$4"

    # Buat payload JSON
    payload=$(jq -n --arg input_file "$input_file" \
                     --arg output_folder "$output_folder" \
                     --arg after_transcode_folder "$after_transcode_folder" \
                     --arg watermark "$watermark" \
                     '{input_file: $input_file, output_folder: $output_folder, after_transcode_folder: $after_transcode_folder, watermark: $watermark}')

    # Tambahkan ke antrian Redis
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LPUSH transcode_queue "$payload"
    echo "Tugas untuk file $input_file ditambahkan ke antrian Redis."
}

# Fungsi untuk memantau perubahan dalam folder input dan menjalankan fungsi transcode_video
monitor_input_changes() {
    local input_folder="$1"
    local output_folder="$2"
    local after_transcode_folder="$3"
    local watermark="$4"

    inotifywait -m -e create,close_write,move,modify --format '%w%f' "$input_folder" | while read -r input_file; do
        echo "File $input_file telah berubah atau dipindahkan. Menambahkan ke antrian transcode..."

        # Tambahkan tugas ke antrian Redis
        add_to_redis_queue "$input_file" "$output_folder" "$after_transcode_folder" "$watermark"
    done
}

# Folder location
input_folder="/app/input"
output_folder="/app/output"
after_transcode_folder="/app/raw-vids"
watermark="/app/watermark/watermark-rplus.png"

# Variabel lingkungan untuk Redis
export REDIS_HOST="redis"
export REDIS_PORT="6379"

# Memulai pemantauan perubahan di folder input
monitor_input_changes "$input_folder" "$output_folder" "$after_transcode_folder" "$watermark" &
echo "Pemantauan perubahan di folder input dimulai..."

# Menunggu sampai proses pemantauan selesai
wait
