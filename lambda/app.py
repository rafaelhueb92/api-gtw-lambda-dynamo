import os
import boto3
import json

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.getenv('DYNAMODB_TABLE'))

def lambda_handler(event, context):
    http_method = event.get("httpMethod")
    
    if http_method == "POST":
        try:
            body = json.loads(event["body"])
            item = {
                "id": f"{body['type']}#{body['nameDashboard']}",
                "values": body["values"]
            }
            table.put_item(Item=item)
            return {
                "statusCode": 201,
                "body": json.dumps({"message": "Item created successfully"})
            }
        except Exception as e:
            return {"statusCode": 400, "body": json.dumps({"error": str(e)})}
    
    elif http_method == "GET":
        type_prefix = event["queryStringParameters"].get("type", "")
        response = table.scan(
            FilterExpression="begins_with(id, :prefix)",
            ExpressionAttributeValues={":prefix": type_prefix}
        )
        return {"statusCode": 200, "body": json.dumps(response["Items"])}

    return {"statusCode": 400, "body": json.dumps({"message": "Invalid HTTP Method"})}
