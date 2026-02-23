#!/usr/bin/env python3
"""Quick test to verify Tapo HTTP API authentication.
Usage: python3 test_tapo_auth.py <host> <username> <password>
"""
import sys
import hashlib

def test_auth(host, user, password):
    """Test authentication against the Tapo camera."""
    try:
        from pytapo import Tapo
        print(f"Connecting to {host} as {user}...")
        tapo = Tapo(host, user, password, printDebugInformation=True)
        info = tapo.getBasicInfo()
        print(f"\nSUCCESS! Camera info: {info.get('device_info', {}).get('basic_info', {}).get('device_model', 'unknown')}")
        
        # Try getting events
        try:
            events = tapo.getEvents()
            print(f"Events found: {len(events)}")
            for event in events[:5]:
                print(f"  - type={event.get('type', '?')}, start={event.get('start_time', '?')}")
        except Exception as e:
            print(f"Events query failed (may not have SD card): {e}")
        
        return True
    except Exception as e:
        print(f"\nFAILED: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 test_tapo_auth.py <host> <username> <password>")
        print("  Try with your camera account password first")
        print("  Then try with your TP-Link cloud account password")
        sys.exit(1)
    
    host = sys.argv[1]
    user = sys.argv[2]
    password = sys.argv[3]
    
    # Show what hashes we're computing
    md5 = hashlib.md5(password.encode("utf8")).hexdigest().upper()
    sha256 = hashlib.sha256(password.encode("utf8")).hexdigest().upper()
    print(f"MD5(password) prefix: {md5[:16]}...")
    print(f"SHA256(password) prefix: {sha256[:16]}...")
    
    test_auth(host, user, password)
