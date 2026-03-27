import subprocess
try:
    print("Starting process...")
    res = subprocess.run(["git", "status"], capture_output=True, text=True)
    print("STDOUT:", res.stdout)
    print("STDERR:", res.stderr)
    print("EXIT:", res.returncode)
except Exception as e:
    print("ERROR:", e)
