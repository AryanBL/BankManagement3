# Connect and run the frontend

## 1. Start the backend

Open a terminal in the Node.js backend folder:

```bash
npm install
npm run dev
```

The frontend expects the backend at:

```text
http://127.0.0.1:4000
```

Confirm it is running by opening:

```text
http://127.0.0.1:4000/api/health
```

## 2. Allow the frontend origin in CORS

In the backend `.env` file, set:

```env
CORS_ORIGIN=http://127.0.0.1:5500,http://localhost:5500
```

Restart the backend after changing `.env`.

## 3. Start the frontend

No frontend dependencies need to be installed.

### Windows

Double-click:

```text
start-frontend.cmd
```

Or run:

```bash
npm start
```

### PowerShell

```powershell
.\start-frontend.ps1
```

### macOS/Linux

```bash
./start-frontend.sh
```

## 4. Open the application

Open:

```text
http://127.0.0.1:5500
```

Do not open `index.html` using a `file:///` URL.

## 5. Change the API address when needed

On the login page, select **Connection settings**, enter the backend base URL, and select **Save and test**.

Enter only the base URL, for example:

```text
http://192.168.1.20:4000
```

Do not append `/api`.

## 6. Sign in

Use an existing application username and password. The frontend calls `/api/auth/me` after login and automatically opens the page for the highest effective role:

```text
Customer → Employee → Admin → HighAdmin
```

## Troubleshooting

### API unavailable

Check that:

- the backend terminal is still running;
- `/api/health` returns JSON;
- the frontend API address is correct;
- the backend `CORS_ORIGIN` includes the exact frontend origin;
- the backend was restarted after editing `.env`.

### Login returns 429

The backend limits repeated login attempts. Restart the backend during local development or wait for the limiter window to expire.

### Port 5500 is already in use

Start on another port:

**Windows Command Prompt:**

```cmd
set FRONTEND_PORT=5501 && npm start
```

**PowerShell:**

```powershell
$env:FRONTEND_PORT=5501; npm start
```

Then add the new frontend origin to `CORS_ORIGIN` and open the matching address.
