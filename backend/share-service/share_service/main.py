import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response

from .core.config import get_settings
from .routers import auth, feedback, health, publish, share, viewer


def create_app() -> FastAPI:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = get_settings()
    app = FastAPI(title="ItsMapPin Share Service", version="0.1.0")

    # §九: CORS for the AGC Hosting H5 viewer + local dev origins.
    # 上架硬性要求：必须显式配置允许来源，禁止隐式 "*" 回退。
    # 本地开发若想放开，显式设 CORS_ORIGINS=* 即可。
    if not settings.cors_origins:
        raise RuntimeError(
            "CORS_ORIGINS env var is required (comma-separated origins, "
            "or '*' to explicitly allow any). Refusing to fall back to '*' silently."
        )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Dev-Uid"],
    )

    # ---- v1.0.4: HEAD → GET 路由复用 -----------------------------------------
    # 微信 / QQ / Telegram 等社交 app 的卡片爬虫普遍先用 HEAD 探一下 URL 和
    # og:image，确认状态码 + content-type 后再决定要不要 GET 完整 body 抓
    # meta 标签和图片。我们的 FastAPI GET 路由没显式注册 HEAD，HEAD 直接
    # 405 → 爬虫放弃 → 卡片只剩 title（systemShare 那边带过去的），描述和
    # 图片全空白。
    #
    # 修法：在路由分发前把 HEAD 改写成 GET，handler 照常跑，最后只回头部、
    # 把 body 丢掉（HEAD 的语义本就如此）。FileResponse 在 HEAD 下仍会读
    # 文件计算 Content-Length，但不写流，开销可接受。
    @app.middleware("http")
    async def head_as_get(request: Request, call_next):
        if request.method != "HEAD":
            return await call_next(request)
        request.scope["method"] = "GET"
        response = await call_next(request)
        # 保留所有头（含 Content-Length / Content-Type / Cache-Control 等），
        # 不写 body 给 client（Starlette 的 Response with no body 即可）。
        passthrough = {
            k: v for k, v in response.headers.items()
            # transfer-encoding 是 hop-by-hop 的，HEAD 自己 ASGI 层会重算
            if k.lower() != "transfer-encoding"
        }
        return Response(status_code=response.status_code, headers=passthrough)

    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(share.router)
    app.include_router(publish.router)
    app.include_router(viewer.router)
    app.include_router(feedback.router)
    return app


app = create_app()
