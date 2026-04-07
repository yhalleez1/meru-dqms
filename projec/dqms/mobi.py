import requests

url = "https://app.mobitechtechnologies.com/sms/sendsms"

headers = {
    "h_api_key": "4575d6f769777051dde88e3798b5f3f6dc6868d5c",
    "Content-Type": "application/json"
}

payload = {
    "mobile": "+25470",
    "response_type": "json",
    "sender_name": "FURCLE",
    "service_id": 0,
    "message": "Hello, just testing for SMS working!"
}

response = requests.post(url, headers=headers, json=payload)

print(response.status_code)
print(response.text)
