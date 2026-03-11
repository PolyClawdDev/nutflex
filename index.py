"""Vercel entrypoint: expose the FastAPI app for serverless deployment."""
from main import app

__all__ = ["app"]
