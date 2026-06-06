import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google.cloud import aiplatform

app = FastAPI()

PROJECT_ID = os.environ.get("PROJECT_ID", "taxi-tips-mlops-dev")
REGION = os.environ.get("REGION", "europe-west1")

# Global variable to cache the endpoint so we don't look it up every time
_vertex_endpoint = None

class TripData(BaseModel):
    trip_distance: float
    fare_amount: float
    duration_min: float

@app.get("/")
def read_root():
    return {"message": "Taxi Tip Proxy API is live and ready to connect to Vertex AI!"}

def get_vertex_endpoint():
    """Lazily connects to Vertex AI only when needed."""
    global _vertex_endpoint
    if _vertex_endpoint is None:
        print("Initializing Vertex AI SDK...")
        aiplatform.init(project=PROJECT_ID, location=REGION)
        
        print("Searching for Endpoint...")
        endpoints = aiplatform.Endpoint.list(filter='display_name="taxi-tip-endpoint"')
        if not endpoints:
            raise RuntimeError("Vertex AI Endpoint 'taxi-tip-endpoint' not found. Is it deployed?")
        
        _vertex_endpoint = endpoints[0]
        print(f"Connected to Endpoint ID: {_vertex_endpoint.name}")
        
    return _vertex_endpoint

@app.post("/predict")
def predict_tip(trip: TripData):
    try:
        # 1. Connect to Vertex (only happens once on the first request)
        endpoint = get_vertex_endpoint()
        
        # 2. Format the payload
        instances = [{
            "trip_distance": trip.trip_distance,
            "fare_amount": trip.fare_amount,
            "duration_min": trip.duration_min
        }]
        
        # 3. Get prediction
        response = endpoint.predict(instances=instances)
        
        return {
            "source": "Vertex AI Model Registry",
            "predicted_tip": response.predictions[0]
        }
    except Exception as e:
        # If something fails, return the exact error cleanly instead of crashing
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)