import requests

url = "https://app.mobitechtechnologies.com/sms/sendsms"

headers = {
    "h_api_key": "4575d6f769777051dde88e8f1987bcf2d9a94cf5e649d3798b5f3f6dc6868d5c",
    "Content-Type": "application/json"
}

payload = {
    "mobile": "+254700753710",
    "response_type": "json",
    "sender_name": "FULL_CIRCLE",
    "service_id": 0,
    "message": "Hello Suro, just testing for SMS working!"
}

response = requests.post(url, headers=headers, json=payload)

print(response.status_code)
print(response.text)
