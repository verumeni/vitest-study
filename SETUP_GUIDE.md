# Vitest 学習プロジェクト 構築手順書

対象:
- TypeScript 実装
- Vitest で単体テスト
- Vitest + 実 DB(PostgreSQL) で結合テスト
- Docker で `app` と `db` を構築
- E2E テスト(Playwright)

## 1. 先に決める技術スタック

最小構成(学習しやすさ重視):
- Node.js 22 LTS
- パッケージ管理: `npm` (pnpm/yarn でも可)
- Web API: `express`
- ORM: `prisma`
- Test Runner: `vitest`
- E2E: `playwright`
- DB: `postgres:16`

## 2. 初期化

```bash
npm init -y
npm i express @prisma/client zod dotenv
npm i -D typescript tsx @types/node @types/express vitest @vitest/coverage-v8 supertest @types/supertest prisma playwright
npx tsc --init
npx prisma init
```

`package.json` scripts を追加:

```json
{
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js",
    "db:generate": "prisma generate",
    "db:migrate": "prisma migrate dev",
    "db:deploy": "prisma migrate deploy",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:unit": "vitest run --project unit",
    "test:integration": "vitest run --project integration",
    "test:e2e": "playwright test"
  }
}
```

## 3. 推奨ディレクトリ構成

```txt
.
├─ src/
│  ├─ app.ts
│  ├─ server.ts
│  ├─ db/
│  │  └─ client.ts
│  └─ routes/
│     └─ users.ts
├─ tests/
│  ├─ unit/
│  ├─ integration/
│  └─ e2e/
├─ prisma/
│  └─ schema.prisma
├─ docker/
│  └─ app.Dockerfile
├─ compose.yaml
├─ vitest.config.ts
├─ playwright.config.ts
└─ .env
```

## 4. Docker 構築(app + db)

`docker/app.Dockerfile`:

```dockerfile
FROM node:22-bookworm-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "run", "start"]
```

`compose.yaml`:

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: apppass
      POSTGRES_DB: appdb
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 5s
      timeout: 5s
      retries: 20
    volumes:
      - pgdata:/var/lib/postgresql/data

  app:
    build:
      context: .
      dockerfile: docker/app.Dockerfile
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://appuser:apppass@db:5432/appdb?schema=public
      PORT: 3000
    ports:
      - "3000:3000"

volumes:
  pgdata:
```

## 5. Prisma 設定

`prisma/schema.prisma`:

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String
  createdAt DateTime @default(now())
}
```

初回マイグレーション:

```bash
docker compose up -d db
npx prisma migrate dev --name init
```

## 6. Vitest 設定(単体/結合を分離)

`vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true
  },
  projects: [
    {
      test: {
        name: "unit",
        include: ["tests/unit/**/*.test.ts"],
        environment: "node"
      }
    },
    {
      test: {
        name: "integration",
        include: ["tests/integration/**/*.test.ts"],
        environment: "node",
        hookTimeout: 30_000,
        testTimeout: 30_000
      }
    }
  ]
});
```

## 7. E2E(Playwright) 設定

`playwright.config.ts`:

```ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "tests/e2e",
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry"
  },
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000/health",
    reuseExistingServer: true,
    timeout: 120_000
  }
});
```

ブラウザ取得:

```bash
npx playwright install
```

## 8. サンプル実装(最小)

`src/app.ts`:

```ts
import express from "express";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  return app;
}
```

`src/server.ts`:

```ts
import { createApp } from "./app";

const port = Number(process.env.PORT ?? 3000);
createApp().listen(port, () => {
  console.log(`server listening on ${port}`);
});
```

## 9. テスト例

単体テスト `tests/unit/health.test.ts`:

```ts
import request from "supertest";
import { createApp } from "../../src/app";

describe("GET /health", () => {
  it("returns ok true", async () => {
    const res = await request(createApp()).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
  });
});
```

結合テスト(実 DB) `tests/integration/user.integration.test.ts`:

```ts
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

describe("db integration", () => {
  beforeAll(async () => {
    await prisma.$connect();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it("can create and read user", async () => {
    const created = await prisma.user.create({
      data: { email: `u${Date.now()}@example.com`, name: "Taro" }
    });

    const found = await prisma.user.findUnique({ where: { id: created.id } });
    expect(found?.name).toBe("Taro");
  });
});
```

E2E テスト `tests/e2e/health.e2e.spec.ts`:

```ts
import { test, expect } from "@playwright/test";

test("health endpoint", async ({ request }) => {
  const res = await request.get("/health");
  expect(res.ok()).toBeTruthy();
  await expect(res.json()).resolves.toEqual({ ok: true });
});
```

## 10. E2E テストケース提案

最初は以下 5 ケースで十分です:
1. `GET /health` が 200 + `{ ok: true }`
2. ユーザー新規作成 API が 201 を返す
3. 作成したユーザー取得 API が正しいデータを返す
4. バリデーション NG(不正 email など)で 400 を返す
5. 存在しないユーザー取得で 404 を返す

画面ありアプリの場合は次を追加:
1. フォーム入力 -> 保存 -> 一覧に反映
2. 必須未入力時のエラー表示
3. 再読み込み後もデータが保持される

## 11. 実行順序(毎回)

```bash
# 1) DB 起動
docker compose up -d db

# 2) マイグレーション
npx prisma migrate deploy

# 3) 単体テスト
npm run test:unit

# 4) 結合テスト
DATABASE_URL=postgresql://appuser:apppass@localhost:5432/appdb?schema=public npm run test:integration

# 5) E2E
npm run test:e2e
```

PowerShell の場合:

```powershell
$env:DATABASE_URL="postgresql://appuser:apppass@localhost:5432/appdb?schema=public"
npm run test:integration
```

## 12. 「上記以外に必要なもの」はあるか？

必須に近い追加項目:
- `.env` / `.env.test` の分離
- DB 初期データ投入(seed)スクリプト
- `beforeEach` での DB クリーンアップ方針
- CI (GitHub Actions など) で `unit + integration + e2e` を自動実行

余裕があれば:
- ESLint + Prettier
- Husky + lint-staged
- Testcontainers(結合テストの DB をテストごとに隔離)

---

この手順で、学習用途としては十分に実践的な構成になります。最初は PostgreSQL 1 本で進め、必要になってから MySQL 版を追加するのがおすすめです。
