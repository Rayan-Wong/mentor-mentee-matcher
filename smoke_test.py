import io
import pandas as pd
import requests

BASE_URL = "https://app.elb.localhost.localstack.cloud:4566"

def test_health_endpoint():
    """Test health check endpoint"""
    print("Testing /health endpoint...")
    response = requests.get(f"{BASE_URL}/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    print("[PASS] Health endpoint working")

def test_homepage_loads():
    """Test homepage loads"""
    print("Testing homepage...")
    response = requests.get(BASE_URL)
    assert response.status_code == 200
    assert "Mentor-Mentee Matching" in response.text
    print("[PASS] Homepage loads successfully")

def test_file_upload_and_match():
    """Test file upload and matching with real column names"""
    print("Testing file upload and matching...")
    
    # Create sample mentor Excel with actual column names
    mentors = pd.DataFrame({
        'Mentor Name': ['Alice Smith', 'Bob Jones'],
        'Mentor Company Category': ['Technology', 'Healthcare'],
        'Areas of Industry Experience': ['Software;AI', 'Medical;Research'],
        'Mentor Job Role Category': ['Engineer', 'Manager'],
        'Mentor Area of Interests Keywords': ['AI, Machine Learning', 'Leadership, Strategy'],
        'Mentor Combined Keywords-Cleaned': ['python, cloud, AI', 'management, healthcare']
    })
    
    # Create sample mentee Excel with actual column names
    mentees = pd.DataFrame({
        'UG_Full_Name': ['Charlie Brown', 'Diana Prince'],
        'Mentee 1st Choice of Industry': ['Technology', 'Healthcare'],
        'Mentee 2nd Choice of Industry': ['Software', 'Medical'],
        'Mentee 3rd Choice of Industry': ['AI', 'Research'],
        'Mentee Job Role Category': ['Engineer', 'Manager'],
        'Mentee Area of Personal Interest': ['AI, Learning', 'Leadership, Growth'],
        'Mentee Keywords': ['python, learning', 'management, strategy']
    })
    
    # Save to BytesIO (in-memory files)
    mentor_file = io.BytesIO()
    mentee_file = io.BytesIO()
    mentors.to_excel(mentor_file, index=False, engine='openpyxl')
    mentees.to_excel(mentee_file, index=False, engine='openpyxl')
    mentor_file.seek(0)
    mentee_file.seek(0)
    
    # Upload files
    files = {
        'mentors': ('mentors.xlsx', mentor_file, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        'mentees': ('mentees.xlsx', mentee_file, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    }
    data = {
        'fuzzy_threshold': '80',
        'priorities': 'industry,role,interest,keyword'
    }
    
    response = requests.post(f"{BASE_URL}/match", files=files, data=data)
    assert response.status_code == 200
    assert "Matching Results" in response.text
    print("[PASS] File upload and matching successful")
    print(f"       Response size: {len(response.text)} bytes")

def test_download_endpoint():
    """Test CSV download after matching"""
    print("Testing /download endpoint...")
    response = requests.get(f"{BASE_URL}/download")
    assert response.status_code == 200
    assert 'text/csv' in response.headers.get('Content-Type', '')
    print("[PASS] Download endpoint working")

if __name__ == "__main__":
    print("=" * 60)
    print("SMOKE TEST - Mentor-Mentee Matcher")
    print("=" * 60)
    print(f"Target: {BASE_URL}")
    print()
    
    tests = [
        test_health_endpoint,
        test_homepage_loads,
        test_file_upload_and_match,
        test_download_endpoint,
    ]
    
    passed = 0
    failed = 0
    
    for test_func in tests:
        try:
            test_func()
            passed += 1
        except AssertionError as e:
            print(f"[FAIL] {test_func.__name__}: {e}")
            failed += 1
        except requests.exceptions.ConnectionError:
            print(f"[FAIL] {test_func.__name__}: Cannot connect to {BASE_URL}")
            print("       Make sure the Flask app is running: python match_mentors.py")
            failed += 1
            break
        except Exception as e:
            print(f"[FAIL] {test_func.__name__}: {e}")
            failed += 1
    
    print()
    print("=" * 60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("=" * 60)
    
    exit(0 if failed == 0 else 1)