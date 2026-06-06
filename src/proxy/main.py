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
    return {"message": "Taxi Tip Proxy API is live and connected to Vertex AI and BigQuery and hopefully robustly handling data validation and errors!"}

@app.post("/predict")
def predict_tip(trip: TripData):
    try:
        # 1. Define the exact feature order the XGBoost model was TRAINED on.
        # This acts as an anchor. Even if the Pydantic model changes, this protects the ML model.
        EXPECTED_FEATURES = ["trip_distance", "fare_amount", "duration_min"]
        
        # 2. Convert the incoming Pydantic object to a standard Python dictionary
        # (Since you are using pydantic==2.10.4, model_dump() is the correct method)
        trip_dict = trip.model_dump()
        
        # 3. Dynamically build the 2D array. 
        # This guarantees the list is built in the exact order of EXPECTED_FEATURES.
        instances = [[trip_dict[feature] for feature in EXPECTED_FEATURES]]
        
        # Forward the request over the network to Vertex AI
        response = endpoint.predict(instances=instances)
        
        # Extract the prediction result
        prediction_result = response.predictions[0]
        
        return {
            "source": "Vertex AI Model Registry",
            "prediction_raw": prediction_result
        }
    except KeyError as e:
        # Catch if a required feature is somehow missing from the dictionary
        raise HTTPException(status_code=400, detail=f"Missing required feature for prediction: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)