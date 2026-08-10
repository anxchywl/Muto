from fastapi import APIRouter

from app.api.favorites import router as favorites_router
from app.api.health import router as health_router
from app.api.images import router as images_router
from app.api.listings import router as listings_router
from app.api.operations import router as operations_router
from app.api.reports import router as reports_router
from app.api.sellers import router as sellers_router

router = APIRouter()
router.include_router(health_router)
router.include_router(images_router)
router.include_router(listings_router)
router.include_router(favorites_router)
router.include_router(sellers_router)
router.include_router(reports_router)
router.include_router(operations_router)
