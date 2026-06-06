import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google.cloud import aiplatform

app = FastAPI()

# 1. Grab environment variables (we will inject these via Terraform)
PROJECT_ID = os.environ.get("PROJECT_ID", "taxi-tips-mlops-dev")
REGION = os.environ.get("REGION", "europe-west1")

# 2. Initialize the Vertex AI SDK
aiplatform.init(project=PROJECT_ID, location=REGION)

# 3. Find our Vertex AI Endpoint dynamically by its display name
print("Connecting to Vertex AI Endpoint...")
endpoints = aiplatform.Endpoint.list(filter='display_name="taxi-tip-endpoint"')
if not endpoints:
    raise RuntimeError("Vertex AI Endpoint 'taxi-tip-endpoint' not found. Is it deployed?")
endpoint = endpoints[0]
print(f"Successfully connected to Endpoint ID: {endpoint.name}")

# Define the data structure we expect the user to send us
class TripData(BaseModel):
    trip_distance: float
    fare_amount: float
    duration_min: float

@app.get("/")
def read_root():
    return {"message": "Taxi Tip Proxy API is live and connected to Vertex AI!"}

@app.post("/predict")
def predict_tip(trip: TripData):
    try:
        # Vertex AI (for BQML XGBoost models) expects instances as a list of dictionaries
        instances = [{
            "trip_distance": trip.trip_distance,
            "fare_amount": trip.fare_amount,
            "duration_min": trip.duration_min
        }]
        
        # Forward the request over the network to Vertex AI
        response = endpoint.predict(instances=instances)
        
        # Extract the prediction result from Vertex AI's response format
        prediction_result = response.predictions[0]
        
        return {
            "source": "Vertex AI Model Registry",
            "prediction_raw": prediction_result
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)