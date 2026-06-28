# Lambda container image. The AWS Lambda Web Adapter bridges the Function URL
# (RESPONSE_STREAM) to a normal uvicorn server, so the same FastAPI app runs
# locally and on Lambda. The AWS-Docs MCP server is pip-installed at build time
# (no runtime PyPI fetch) and launched as a stdio subprocess by the app.
FROM public.ecr.aws/docker/library/python:3.12-slim

# AWS Lambda Web Adapter (extension) — enables Lambda response streaming.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter
ENV AWS_LWA_INVOKE_MODE=response_stream \
    AWS_LWA_PORT=8080 \
    PORT=8080 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY pyproject.toml ./
COPY app ./app
RUN pip install --no-cache-dir .

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
