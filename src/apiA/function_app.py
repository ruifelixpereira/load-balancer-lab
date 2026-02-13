import azure.functions as func
import json
import datetime

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    """Health-check endpoint – useful for LB probes and quick validation."""
    return func.HttpResponse(
        json.dumps(
            {
                "status": "healthy",
                "api": "apiA",
                "timestamp": datetime.datetime.utcnow().isoformat(),
            }
        ),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="hello", methods=["GET", "POST"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    """Simple greeting endpoint that identifies this as API A."""
    name = req.params.get("name")
    if not name:
        try:
            body = req.get_json()
            name = body.get("name")
        except ValueError:
            pass
    name = name or "World"

    return func.HttpResponse(
        json.dumps({"message": f"Hello, {name}! This is API A.", "api": "apiA"}),
        mimetype="application/json",
        status_code=200,
    )
