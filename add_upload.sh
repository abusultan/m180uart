#!/bin/bash
cd /var/www/cutter

cat << 'EOF' > app/Http/Controllers/Api/ScreensaverController.php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Screensaver;
use Illuminate\Http\Request;

class ScreensaverController extends Controller
{
    public function index()
    {
        $screensavers = Screensaver::where('is_active', true)->get();
        
        $images = $screensavers->map(function ($screensaver) {
            return $screensaver->image_url;
        });

        return response()->json([
            'success' => true,
            'images' => $images
        ]);
    }

    public function uploadForm()
    {
        $screensavers = Screensaver::orderBy('created_at', 'desc')->get();
        
        $html = '<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>رفع صور شاشة التوقف</title>
    <style>
        body { font-family: Tahoma, Arial; background: #f4f4f9; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { text-align: center; color: #333; }
        .form-group { margin-bottom: 15px; }
        input[type="file"] { display: block; margin-top: 5px; }
        button { background: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        button:hover { background: #0056b3; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px; margin-top: 30px; }
        .card { border: 1px solid #ddd; padding: 10px; border-radius: 5px; text-align: center; }
        .card img { max-width: 100%; height: auto; border-radius: 4px; }
        .success { background: #d4edda; color: #155724; padding: 10px; border-radius: 4px; margin-bottom: 20px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>إدارة إعلانات شاشة التوقف</h1>
        
        <form action="/api/screensaver-upload" method="POST" enctype="multipart/form-data">
            <div class="form-group">
                <label>اختر صورة (JPG, PNG):</label>
                <input type="file" name="image" required accept="image/*">
            </div>
            <button type="submit">رفع الصورة</button>
        </form>

        <h2>الصور الحالية المرفوعة</h2>
        <div class="grid">';
        
        foreach ($screensavers as $s) {
            $status = $s->is_active ? "مفعل" : "معطل";
            $html .= '<div class="card">
                <img src="'.$s->image_url.'" alt="Image">
                <p>الحالة: '.$status.'</p>
            </div>';
        }

        $html .= '</div>
    </div>
</body>
</html>';

        return response($html);
    }

    public function uploadImage(Request $request)
    {
        if ($request->hasFile('image')) {
            $path = $request->file('image')->store('screensavers', 'public');
            Screensaver::create([
                'image_path' => $path,
                'is_active' => true
            ]);
            return redirect('/api/screensaver-upload?success=1');
        }
        return "No image uploaded.";
    }
}
EOF

# Append the new routes to routes/api.php
grep -q "uploadForm" routes/api.php || cat << 'EOF' >> routes/api.php

Route::get('/screensaver-upload', [ScreensaverController::class, 'uploadForm']);
Route::post('/screensaver-upload', [ScreensaverController::class, 'uploadImage']);
EOF

# Ensure symbolic link exists
php artisan storage:link
