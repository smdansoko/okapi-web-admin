FROM python:3.13-slim

WORKDIR /app

# System deps (fonts needed for reportlab PDF generation with custom fonts)
RUN apt-get update && apt-get install -y --no-install-recommends \
    fontconfig \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Persist the SQLite database and JSON data files across deploys via a volume
VOLUME ["/app/data"]

ENV PORT=5070
EXPOSE 5070

# gunicorn production server: 2 workers, 120s timeout for PDF/Excel generation
CMD ["sh", "-c", "gunicorn -w 2 -b 0.0.0.0:${PORT} --timeout 120 app:app"]
