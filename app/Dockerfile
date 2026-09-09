FROM python:3.11-slim

WORKDIR /app

# Install dependencies first for layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Expose port (matches containerPort in Helm chart values)
EXPOSE 8080

# Non-root user for security best practice
RUN useradd -m -u 1001 appuser
USER appuser

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
