import os
from fastapi import FastAPI
from pydantic import BaseModel
import joblib

app = FastAPI()

model = joblib.load('model.joblib')


class TripData(BaseModel):
    trip_distance: float
    fare_amount: float
    duration_min: float
    
@app.get("/")
def read_root():
    return {"message": "Taxi Tip Prediction API is live! and deployed on Cloud Run."}

@app.post("/predict")
def predict_tip(trip: TripData):
    
    features = [[trip.trip_distance, trip.fare_amount, trip.duration_min]]
    tip_prediction = model.predict(features)[0]
    return {"predicted_tip": tip_prediction}
    
if __name__ == "__main__":
    # Get the port from the environment, defaulting to 8080 if it's missing (local dev)
    port = int(os.environ.get("PORT", 8080))
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=port)
    