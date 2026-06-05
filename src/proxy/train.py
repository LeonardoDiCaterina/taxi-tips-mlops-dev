import joblib
from sklearn.linear_model import LinearRegression

def train_model():
    # 1. Dummy training data 
    # Features: [trip_distance (miles), fare_amount ($), duration (minutes)]
    X = [
        [2.5, 10.0, 12.0], 
        [1.0, 5.0, 6.0], 
        [5.0, 20.0, 25.0], 
        [10.0, 45.0, 40.0],
        [3.2, 12.5, 15.0]
    ]
    
    # Target: tip_amount ($)
    y = [2.0, 1.0, 5.0, 10.0, 2.5]

    # 2. Train the model
    print("Training the Taxi Tip prediction model...")
    model = LinearRegression()
    model.fit(X, y)

    # 3. Save the model to a file
    print("Saving model to model.joblib...")
    joblib.dump(model, 'model.joblib')
    print("Done! Model is ready for production.")

if __name__ == "__main__":
    train_model()