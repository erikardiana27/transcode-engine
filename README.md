This project is designed to create a Docker container using the latest Ubuntu image as the base. The container is set up with several tools including ffmpeg, inotify-tools, taskset, task-spooler, jq, and redis-tools. Additionally, it includes a script for monitoring a directory and processing video files with a watermark.


Directory Structure
/app/input: Directory to monitor for new video files.

/app/output: Directory to save processed video files.

/app/raw-vids: Directory for raw video storage.

/app/watermark: Directory containing watermark images.

/app/queue: Directory for task queue management.

/app/log-file: Directory for log files.

Log Files

/app/log-file/watcher and transcode.log: Log file for monitoring script actions.

