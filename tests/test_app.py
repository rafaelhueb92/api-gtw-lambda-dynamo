import app

def test_create_dashboard():
    event = {
        "httpMethod": "POST",
        "body": '{"type": "dashboard", "nameDashboard": "Main", "values": "test data"}'
    }
    response = app.lambda_handler(event, None)
    assert response["statusCode"] == 201

def test_get_dashboards():
    event = {
        "httpMethod": "GET",
        "queryStringParameters": {"type": "dashboard"}
    }
    response = app.lambda_handler(event, None)
    assert response["statusCode"] == 200
