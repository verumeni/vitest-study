FROM node:22-bookworm-slim

# 作業ディレクトリを固定
WORKDIR /app

# 依存キャッシュを効かせるため先に package*.json だけコピー (パスはcompose.yaml > context が基準)
COPY package*.json ./
RUN npm ci

# アプリ本体をコピーしてビルド COPY <src> <dest>
COPY . .
RUN npm run build

# アプリが待ち受けるポート
EXPOSE 3000

# コンテナ起動時のコマンド(シェル未使用の書き方)
CMD ["npm", "run", "start"]