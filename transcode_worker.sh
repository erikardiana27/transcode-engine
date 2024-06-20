#!/bin/bash

LOGFILE="/app/log-file/transcode.log"

# Fungsi untuk mencatat log
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOGFILE"
}

# Debug: cek apakah direktori dan file log bisa ditulis
echo "Memulai skrip transcode_worker.sh"
echo "LOGFILE = $LOGFILE"
ls -l /app/log-file
touch "$LOGFILE"
echo "Log file created" | tee -a "$LOGFILE"

# Fungsi untuk melakukan transcode video (sama seperti yang sebelumnya)
transcode_video() {
    local input_file="$1"
    local output_folder="$2"
    local after_transcode_folder="$3"
    local watermark="$4"

    # Mendapatkan nama file tanpa ekstensi
    filename_noext=$(basename -- "$input_file")
    filename_noext="${filename_noext%.*}"
    # Mendapatkan tanggal saat ini
    current_date=$(date +%Y%m%d)
    # Mendapatkan UID
    uid=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 24 | head -n 1)

    # Buat folder output berdasarkan UID
    uid_folder="${output_folder}/${uid}"
    mkdir -p "$uid_folder"

    hls_playlist=""
    dash_playlists=""

    # Resolusi dan bandwidth yang digunakan
    resolutions=("1280x720" "640x360")
    bandwidths=("3000k" "1000k")

    for i in "${!resolutions[@]}"; do
        resolution="${resolutions[$i]}"
        bandwidth="${bandwidths[$i]}"
        
        output_file_base="${uid_folder}/${uid}_${resolution}"

        # Proses transcoding
        log "Transcoding $input_file ke resolusi $resolution dengan bitrate $bandwidth"
        taskset -c 0,1,2,3,4 ffmpeg -i "$input_file" -i "$watermark" -filter_complex "[1:v]scale=150:50,format=rgba,colorchannelmixer=aa=0.5[watermark];[0:v][watermark]overlay=x=main_w-overlay_w-(main_w*0.05):y=main_h-overlay_h-(main_h*0.15)" -s "$resolution" -c:v libx264 -b:v "$bandwidth" -c:a aac -f hls -hls_time 10 -hls_list_size 0 -hls_segment_filename "${output_file_base}_%03d.ts" "${output_file_base}.m3u8" -f dash -use_timeline 1 -use_template 1 "${output_file_base}.mpd" 2>>"$LOGFILE"
        if [ $? -eq 0 ]; then
            log "Transcoding $input_file ke resolusi $resolution dengan bitrate $bandwidth selesai."
        else
            log "Error: Transcoding $input_file ke resolusi $resolution dengan bitrate $bandwidth gagal."
        fi

        # Tambahkan playlist untuk multi-bitrate
        hls_playlist+="#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth\n${uid}_${resolution}.m3u8\n"
        dash_playlists+="${output_file_base}.mpd|${bandwidth},"
    done

    # Buat file master playlist HLS
    hls_master_playlist="${uid_folder}/${uid}_master.m3u8"
    echo -e "#EXTM3U\n$hls_playlist" > "$hls_master_playlist"
    log "Master playlist HLS dibuat: $hls_master_playlist"

    # Buat file master playlist DASH
    dash_master_playlist="${uid_folder}/${uid}_master.mpd"
    IFS=',' read -ra dash_array <<< "$dash_playlists"
    for entry in "${dash_array[@]}"; do
        if [[ -n "$entry" ]]; then
            file=$(echo $entry | cut -d'|' -f1)
            # Hanya perlu merujuk ke satu playlist MPD, karena isinya akan menyesuaikan otomatis
            echo "$file" > "$dash_master_playlist"
            break
        fi
    done
    log "Master playlist DASH dibuat: $dash_master_playlist"

    # Catat informasi ke file list.ext
    echo -e "UID: $uid\nNama file input: $filename_noext\nTanggal: $current_datetime\n" >> "${output_folder}/list.ext"
    echo -e "URL HLS: https://transxcode.rctiplus.co.id/${uid}/$(basename "$hls_master_playlist")\n" >> "${output_folder}/list.ext"
    echo -e "URL DASH: https://transxcode.rctiplus.co.id/${uid}/$(basename "$dash_master_playlist")\n" >> "${output_folder}/list.ext"
    log "Informasi file dicatat ke ${output_folder}/list.ext"

    # Pindahkan file setelah transcode selesai
    mv "$input_file" "$after_transcode_folder/"
    log "File $input_file telah dipindahkan ke $after_transcode_folder."
}

# Fungsi untuk mengambil dan memproses tugas dari antrian Redis
process_queue() {
    while true; do
        # Ambil tugas dari antrian Redis
        task=$(redis-cli -h redis RPOP transcode_queue)

        # Jika antrian tidak kosong
        if [[ -n "$task" ]]; then
            log "Tugas diambil dari antrian: $task"
            # Parse JSON
            input_file=$(echo "$task" | jq -r '.input_file')
            output_folder=$(echo "$task" | jq -r '.output_folder')
            after_transcode_folder=$(echo "$task" | jq -r '.after_transcode_folder')
            watermark=$(echo "$task" | jq -r '.watermark')

            # Lakukan transcoding
            transcode_video "$input_file" "$output_folder" "$after_transcode_folder" "$watermark"
        else
            log "Antrian kosong, menunggu sebelum cek antrian lagi."
            # Tunggu sebelum cek antrian lagi
            sleep 5
        fi
    done
}

# Jalankan proses queue
log "Memulai proses antrian transcoding"
process_queue