# HomeCloud Device Discovery & Authentication - Integration Guide

This document explains how to implement local and remote device discovery and authentication for HomeCloud-compatible devices. It is intended for teams integrating these features into their own applications.

---

## Overview

The HomeCloud frontend supports two main device connection flows:

- **Local Discovery:** Find and connect to devices on the same local network using mDNS.
- **Remote Access:** Connect to devices remotely via a cloud relay, using secure authentication and device selection.

Both flows share a unified device model and authentication logic, allowing seamless switching between local and remote devices.

---

## 1. Local Device Discovery (mDNS)

### Principle
- Devices advertise themselves on the local network using mDNS with a specific service type (e.g. `_https._tcp` and name `HomeCloud`).
- The app scans for these services, retrieves their IP/hostname, and queries their `/about` and `/status` endpoints to validate and display them.

### Key Steps
1. **Start Discovery**
   - Use an mDNS library (e.g. `nsd` for Flutter) to scan for services of type `_https._tcp` and name containing `HomeCloud`.
   - Example (Flutter):
     ```dart
     final discovery = await nsd.startDiscovery('_https._tcp');
     discovery.addServiceListener((service, status) {
       if (status == ServiceStatus.found && service.name.contains('HomeCloud')) {
         // Handle found device
       }
     });
     ```
2. **Query Device Info**
   - For each found service, build the device base URL (e.g. `https://<host>:<port>/api/v1`).
   - Call `/about` and `/status` endpoints to get device metadata and readiness.
   - Only display devices that are ready (status = `ready`).
3. **Select and Connect**
   - When a user selects a device, store its base URL and use it for subsequent API calls.
   - Authenticate as needed (see Authentication section).

---

## 2. Remote Device Discovery & Access

### Principle
- Users can access their devices remotely via a cloud relay.
- Remote authentication is email-based: the user enters their email, receives a code, and enters it to obtain access tokens.
- The app then fetches the list of remote devices available for that user.

### Key Steps
1. **Initiate Remote Access**
   - User enters their email.
   - Call the remote API to send a code to the user's email.
2. **Validate Code**
   - User enters the received code.
   - Call the remote API to validate the code and obtain access/refresh tokens.
   - **Important:** Store the refresh token securely for future sessions. This allows the app to obtain new access tokens without requiring the user to validate code again.
3. **Fetch Remote Devices**
   - Use the access token to call the remote API and retrieve the list of devices associated with the user.
   - Each device includes a prioritized list of connection paths (local, public, relay), already sorted by the server. Attempt to connect using the paths in the provided order.
4. **Select and Connect**
   - When a user selects a remote device, store its connection info and use it for subsequent API calls.

---

## 3. Authentication & Token Refresh

- Add the Authorization header to each HTTP request as follows:  
    `'Bearer <accessToken>'`, without overriding an existing header (useful in case of a retry).
- If a call returns 401/403, the app should attempt to refresh the access token using the refresh token.
- If refresh fails, prompt the user to re-authenticate.
- The authentication logic is abstracted via the `CuratorAuthProvider` interface and used by both local and remote providers.

---

## 4. Error Handling

- Always handle network errors, timeouts, and invalid responses gracefully.
- Show user-friendly error messages and allow retrying discovery or authentication.
- Log errors for debugging (see `_handleError` in the code).

---

## 5. Key Classes & Interfaces

- `DeviceProvider` (Homecloud device): Handles Homecloud authentication and API calls.
- `RemoteProvider` (remote access server): Handles remote authentication and API calls.
- `CuratorAuthProvider`: Interface for authentication logic (access token, refresh, logout).
- `CuratorInterceptor`/`CuratorAuthenticator`: Chopper interceptors for adding auth headers and handling token refresh.

---

## 6. Security Notes

- All connections use HTTPS (TLS). For Homecloud device, the app may need to trust a custom root CA (see `CuratorHttpClient`).
- Never store access tokens.
- Never store refresh tokens in plain text. Use secure storage.
- Always validate device certificates when connecting.

---

## 7. Useful Endpoints

- Homecloud device:
  - `GET /api/v1/about` — Device info
  - `GET /api/v1/status` — Device status
- Remote API:
  - `POST /client/v1/auth/initiate` — Send code to email
  - `POST /client/v1/auth/token` — Validate code, get tokens
  - `GET /client/v1/devices` — List remote devices
  - `GET /client/v1/auth/refresh` — Refresh remote token

---

## 8. Integration Tips

- Always clean up discovery sessions to avoid leaks.
- Allow the user to switch between local and remote devices easily.
- Provide clear UI feedback during discovery, authentication, and errors.

---

## 9. References
- See `sign_in_screen.dart`, `device.provider.dart`, `remote.provider.dart`, and `auth.api.dart` for implementation details.
- For Flutter, see the `nsd` package for mDNS, and `chopper` for API calls.

---

For any questions or clarifications, contact the HomeCloud frontend team.
