import psycopg2
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

conn = psycopg2.connect(
    host="gondola.proxy.rlwy.net",
    port=23903,
    dbname="railway",
    user="postgres",
    password="RxcBkQEJxHZkCBfTFQhSjtFCjrLDEsfc"
)
cur = conn.cursor()

hashed = pwd_context.hash("test123")
cur.execute(
    "INSERT INTO users (name, username, password_hash) VALUES (%s, %s, %s)",
    ("Juan", "juan", hashed)
)
conn.commit()
cur.close()
conn.close()
print("User created!")