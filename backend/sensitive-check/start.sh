#!/bin/bash
cd /opt/itsmappin/Backend_ItsMapPin/sensitive-check
set -a
source .env
set +a
echo "BIC_API_KEY: ${BIC_API_KEY:0:10}..."  # 调试输出
echo "BIC_SECRET_KEY: ${BIC_SECRET_KEY:0:10}..."  # 调试输出
exec /opt/itsmappin/Backend_ItsMapPin/.venv/bin/python baidu_image_censor.py --host 127.0.0.1 --port 9200
