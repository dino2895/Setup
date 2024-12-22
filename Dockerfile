# 使用輕量級的基礎映像
FROM alpine:latest

# 安裝必要工具
RUN apk add --no-cache bash curl jq tzdata

# 設置工作目錄
WORKDIR /app

# 複製腳本到容器中
COPY cfupdater.sh /app/cfupdater.sh

# 設置腳本可執行權限
RUN chmod +x /app/cfupdater.sh

# 執行腳本
CMD ["/app/cfupdater.sh"]