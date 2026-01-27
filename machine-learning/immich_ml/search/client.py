import requests
import json

# --- Server URL ---
SERVER_URL = "http://127.0.0.1:8000/analyze"

# --- Example text to analyze ---
text_example = """
Photos of riding horses near the Eiffel Tower and Taj Mahal with John Smith and Ann in May 2025.
Subscription from March 1, 2025 to March 31, 2025.
The subscription starts from April 1, 2025.
It is valid until April 30, 2025.
Sailing yesterday.
Cooking this year.
Swimming this week.
Hiking last month.
Hunting past month.
"""

# --- JSON payload ---
payload = {
    "text": text_example,
    "week_start_sunday": False,
    "period_end_mode_current": False,
    "last_as_previous": False
}

print("REQUEST:")
print(json.dumps(payload, indent=4))

# --- Send POST request ---
response = requests.post(SERVER_URL, json=payload)

# --- Check response ---
if response.status_code == 200:
    result = response.json()
    print("RESPONSE:")
    print(json.dumps(result, indent=4))
else:
    print("ERROR:")
    print(f"Error: {response.status_code} - {response.text}")
