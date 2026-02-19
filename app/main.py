from fastapi import FastAPI
from app.routes import instruments, dispatches, auth

app = FastAPI(title="Tool Tracker API", version="1.0")

app.include_router(auth.router)
app.include_router(instruments.router)
app.include_router(dispatches.router)

@app.get("/")
def root():
    return {"message": "Tool Tracker API is running"}

@app.get("/health")
def health():
    return {"status": "ok"}