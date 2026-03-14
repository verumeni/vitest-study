# セットアップ手順

## 1. システムを構成するモジュールのインストール

```bash
npm init -y
npm i express @prisma/client zod dotenv
npm i -D typescript tsx @types/node @types/express vitest @vitest/coverage-v8 supertest @types/supertest prisma playwright
npx tsc --init
npx prisma init
npx playwright install
```

