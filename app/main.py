from fastapi import FastAPI
from app.routes import dispatches, instruments, auth

app = FastAPI(title="AMTEC Tool Tracker API", version="1.3.0")

app.include_router(auth.router)
app.include_router(instruments.router)
app.include_router(dispatches.router)


@app.get("/")
def root():
    return {"message": "AMTEC Tool Tracker API is running"}


@app.get("/health")
def health():
    return {"status": "ok"}