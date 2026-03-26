# ToolTracker - AMTEC Tool Management System

A comprehensive tool tracking and dispatch management system for AMTEC (Agricultural Machinery Testing and Evaluation Center) at UPLB, combining a Flutter mobile app frontend with a Python backend API.

## 📁 Project Structure

```
ToolTracker/
├── tooltracker-app/          # Flutter mobile application
│   ├── lib/                  # Source code
│   │   ├── screens/          # UI screens
│   │   ├── models/           # Data models
│   │   ├── services/         # API & sync services
│   │   ├── database/         # Local SQLite database
│   │   ├── theme/            # Theme configuration
│   │   └── main.dart         # App entry point
│   ├── android/              # Android build files
│   ├── ios/                  # iOS build files
│   ├── pubspec.yaml          # Flutter dependencies
│   └── ...
│
├── tooltracker-backend/      # Python/Flask backend API
│   ├── app/                  # Flask app structure
│   ├── supabase/             # Database migrations
│   ├── requirements.txt       # Python dependencies
│   ├── Procfile              # Deployment config
│   └── ...
│
└── README.md                 # This file
```

## 🚀 Quick Start

### Frontend (Flutter)

```bash
cd tooltracker-app
flutter pub get
flutter run
```

**Requirements:**
- Flutter SDK 3.11.0 or higher
- Android SDK (for Android development)
- iOS SDK (for iOS development - macOS)

### Backend (Python)

```bash
cd tooltracker-backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

**Requirements:**
- Python 3.8+
- Virtual environment (recommended)

## ✨ Features

### Frontend (Flutter)
- **Instrument Management** - Track tools and equipment status, condition, and location
- **Dispatch System** - Create and manage staff/student tool borrowing records
- **Real-time Sync** - Automatic sync with backend when connectivity is available
- **Offline Support** - Full offline capability with SQLite local database
- **Export Functionality** - Export instrument records and dispatch data to Excel
- **Admin Controls** - Admin panel for user management and system oversight
- **Theme System** - 3-mode theme (AMTEC, Light, Dark)
- **Maintenance Scheduling** - Track repair and calibration schedules
- **Activity Logging** - Complete audit trail of all operations

### Backend (Flask/Supabase)
- **RESTful API** - Comprehensive REST endpoints
- **Authentication** - User login and token management
- **Database** - Supabase PostgreSQL with migrations
- **Tool Management** - CRUD operations for tools/instruments
- **Dispatch Tracking** - Staff and student borrowing management
- **User Management** - Admin user administration
- **Messaging System** - Admin-to-user notifications
- **Activity Logging** - Event tracking and monitoring

## 🔧 Tech Stack

### Frontend
- **Flutter** - UI framework
- **Provider** - State management
- **SQLite** - Local database (sqflite)
- **HTTP** - API communication
- **Shared Preferences** - Local storage
- **Excel** - Export functionality
- **Mobile Scanner** - QR/Barcode scanning
- **Camera** - Photo capture
- **Sensors Plus** - Accelerometer access (easter egg feature)

### Backend
- **Python 3.x** - Language
- **Flask** - Web framework
- **Supabase** - PostgreSQL database and auth
- **PostgreSQL** - Primary database
- **SQLAlchemy** - ORM

## 📝 Key Models

### Instrument
```
- instrument_code (unique)
- instrument_name
- serial_number
- current_condition (Functioning, For Repair, Condemning, Condemned)
- status (Available, In Use)
- location
- last_touch_date / last_touch_by
- scheduled_repair_date
- scheduled_condemn_date
- last_calibrated_date
- calibration_notes
```

### Dispatch
```
- dispatch_no (unique)
- test_engineer
- processed_by_id / processed_by_name
- date_out / date_in
- dispatch_type (staff, student)
- remarks
- return_photo_paths
- synced (0/1)
- conflict (0/1)
```

## 🔄 Sync System

The app uses a sophisticated sync mechanism:
- **Connectivity Listener** - Detects network changes
- **Automatic Sync** - Syncs when connection is restored
- **Conflict Detection** - Handles offline edits
- **Hard 30-Second Timeout** - Prevents hanging syncs
- **Offline Queue** - Queues local edits for later sync

## 📦 Database Schema

### SQLite Tables (Mobile)
- `instruments` - Tool records
- `dispatches` - Borrowing transactions
- `dispatch_items` - Items in each dispatch
- `instrument_history` - Event log per instrument
- `condemn_requests` - Equipment disposal requests
- `revert_requests` - Condition change requests
- `activity_log` - System activity tracking
- `admin_messages` - Notifications to users

## 🔐 Security

- **Token-based Auth** - Bearer token in headers
- **Supabase Auth** - Backend authentication
- **API Keys** - Anonymous key for public endpoints
- **Local Encryption** - SharedPreferences for tokens
- **Role-based Access** - Staff vs Admin permissions

## 🚢 Deployment

### Frontend
- **Android** - Built APK for distribution
- **iOS** - Built via Xcode

### Backend
- Deploy using Procfile on platforms like:
  - Heroku
  - Railway
  - Render
  - Custom servers

## 📊 API Endpoints (Backend)

- `POST /login` - User authentication
- `GET /instruments` - Fetch all tools
- `PATCH /instruments/{code}` - Update tool
- `GET /dispatches` - Fetch all transactions
- `POST /dispatches` - Create new dispatch
- And more...

## 🐛 Known Issues & Fixes

### Recently Fixed (v1.2.0)
- ✅ Scheduled dates now preserved through sync
- ✅ Date picker added to return flow
- ✅ Excel exports to Downloads folder
- ✅ Filter chips now show only matched units
- ✅ Upcoming tab shows For Repair/Condemning instruments

## 📞 Support & Contact

For issues or questions, contact the AMTEC Tool Tracker development team.

## 📄 License

This project is proprietary to AMTEC, UPLB.

---

**Version:** 1.2.0  
**Last Updated:** March 26, 2026
