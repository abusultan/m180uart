#!/bin/bash
cd /var/www/cutter

# 1. Overwrite Controller with rotate method
cat << 'EOF' > app/Http/Controllers/Admin/ScreensaverController.php
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Screensaver;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ScreensaverController extends Controller
{
    public function index()
    {
        $screensavers = Screensaver::orderBy('created_at', 'desc')->get();
        return view('admin.screensavers.index', compact('screensavers'));
    }

    public function store(Request $request)
    {
        $request->validate([
            'image' => 'required|image|mimes:jpeg,png,jpg,gif|max:5120',
        ]);

        if ($request->hasFile('image')) {
            $path = $request->file('image')->store('screensavers', 'public');
            Screensaver::create([
                'image_path' => $path,
                'is_active' => true
            ]);
            return back()->with('success', 'تم رفع الصورة بنجاح');
        }

        return back()->with('error', 'حدث خطأ أثناء الرفع');
    }

    public function destroy(Screensaver $screensaver)
    {
        Storage::disk('public')->delete($screensaver->image_path);
        $screensaver->delete();
        return back()->with('success', 'تم حذف الصورة بنجاح');
    }

    public function toggle(Screensaver $screensaver)
    {
        $screensaver->is_active = !$screensaver->is_active;
        $screensaver->save();
        return back()->with('success', 'تم تغيير حالة الصورة');
    }

    public function rotate(Screensaver $screensaver)
    {
        $path = Storage::disk('public')->path($screensaver->image_path);
        if (!file_exists($path)) {
            return back()->with('error', 'ملف الصورة غير موجود');
        }

        $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
        $source = null;

        if ($ext == 'jpg' || $ext == 'jpeg') {
            $source = @imagecreatefromjpeg($path);
        } elseif ($ext == 'png') {
            $source = @imagecreatefrompng($path);
        } elseif ($ext == 'gif') {
            $source = @imagecreatefromgif($path);
        }

        if ($source) {
            // Preserve transparency for PNG and GIF
            if ($ext == 'png' || $ext == 'gif') {
                imagealphablending($source, true);
                imagesavealpha($source, true);
            }

            // Rotate 90 degrees clockwise. In GD, degrees are counter-clockwise, so -90 is clockwise.
            // 0 is the background color, for PNG we use transparent.
            $transparent = imagecolorallocatealpha($source, 0, 0, 0, 127);
            $rotate = imagerotate($source, -90, $transparent);

            if ($ext == 'png' || $ext == 'gif') {
                imagealphablending($rotate, false);
                imagesavealpha($rotate, true);
            }

            // Save back
            if ($ext == 'jpg' || $ext == 'jpeg') {
                imagejpeg($rotate, $path, 90);
            } elseif ($ext == 'png') {
                imagepng($rotate, $path);
            } elseif ($ext == 'gif') {
                imagegif($rotate, $path);
            }
            
            imagedestroy($source);
            imagedestroy($rotate);

            // Add a cache buster timestamp query parameter to image_path temporarily or let frontend handle it
            // The browser might cache the old image, so we add an empty update query string for the view
            return back()->with('success', 'تم تدوير الصورة بنجاح');
        }

        return back()->with('error', 'تعذر تدوير هذه الصورة بسبب صيغتها');
    }
}
EOF

# 2. Overwrite View to add rotate button
cat << 'EOF' > resources/views/admin/screensavers/index.blade.php
@extends('layouts.admin')

@section('content')
<div class="container-fluid">
    <div class="d-sm-flex align-items-center justify-content-between mb-4">
        <h1 class="h3 mb-0 text-gray-800">إدارة شاشة التوقف للماكينة</h1>
    </div>

    @if(session('success'))
        <div class="alert alert-success">{{ session('success') }}</div>
    @endif
    @if(session('error'))
        <div class="alert alert-danger">{{ session('error') }}</div>
    @endif

    <div class="row">
        <!-- Form -->
        <div class="col-md-4 mb-4">
            <div class="card shadow">
                <div class="card-header py-3">
                    <h6 class="m-0 font-weight-bold text-primary">إضافة صورة جديدة</h6>
                </div>
                <div class="card-body">
                    <form action="{{ route('admin.screensavers.store') }}" method="POST" enctype="multipart/form-data">
                        @csrf
                        <div class="mb-3">
                            <label class="form-label">اختر صورة</label>
                            <input type="file" name="image" class="form-control" required accept="image/*">
                        </div>
                        <button type="submit" class="btn btn-primary w-100">رفع الصورة</button>
                    </form>
                </div>
            </div>
        </div>

        <!-- List -->
        <div class="col-md-8 mb-4">
            <div class="card shadow">
                <div class="card-header py-3">
                    <h6 class="m-0 font-weight-bold text-primary">الصور المرفوعة</h6>
                </div>
                <div class="card-body">
                    <div class="table-responsive">
                        <table class="table table-bordered">
                            <thead>
                                <tr>
                                    <th>الصورة</th>
                                    <th>الحالة</th>
                                    <th>التاريخ</th>
                                    <th>إجراءات</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse($screensavers as $s)
                                <tr>
                                    <td width="150" class="text-center">
                                        <!-- Adding a timestamp query to bust browser cache after rotation -->
                                        <img src="{{ $s->image_url }}?v={{ time() }}" alt="" class="img-fluid rounded shadow-sm" style="max-height: 120px;">
                                    </td>
                                    <td class="align-middle">
                                        @if($s->is_active)
                                            <span class="badge bg-success text-white">مفعل</span>
                                        @else
                                            <span class="badge bg-danger text-white">معطل</span>
                                        @endif
                                    </td>
                                    <td class="align-middle">{{ $s->created_at->format('Y-m-d') }}</td>
                                    <td class="align-middle">
                                        <div class="btn-group">
                                            <form action="{{ route('admin.screensavers.toggle', $s) }}" method="POST">
                                                @csrf
                                                <button type="submit" class="btn btn-sm btn-{{ $s->is_active ? 'warning' : 'success' }} me-1">
                                                    <i class="fas fa-power-off"></i> {{ $s->is_active ? 'تعطيل' : 'تفعيل' }}
                                                </button>
                                            </form>
                                            <form action="{{ route('admin.screensavers.rotate', $s) }}" method="POST">
                                                @csrf
                                                <button type="submit" class="btn btn-sm btn-info me-1 text-white">
                                                    <i class="fas fa-sync-alt"></i> تدوير
                                                </button>
                                            </form>
                                            <form action="{{ route('admin.screensavers.destroy', $s) }}" method="POST" onsubmit="return confirm('هل أنت متأكد من الحذف؟')">
                                                @csrf
                                                @method('DELETE')
                                                <button type="submit" class="btn btn-sm btn-danger">
                                                    <i class="fas fa-trash"></i> حذف
                                                </button>
                                            </form>
                                        </div>
                                    </td>
                                </tr>
                                @empty
                                <tr><td colspan="4" class="text-center">لا توجد صور</td></tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
@endsection
EOF

# 3. Add Route
if ! grep -q "screensavers.rotate" routes/web.php; then
# It's tricky to insert into the existing group automatically using sed in a reliable way,
# but we can just append it right after the existing screensavers routes.
# The previous script added:
# Route::resource('screensavers', ...
# Route::post('screensavers/{screensaver}/toggle', ...
sed -i -e '/screensavers\/{screensaver}\/toggle/a\
    Route::post('"'"'screensavers/{screensaver}/rotate'"'"', [\\App\\Http\\Controllers\\Admin\\ScreensaverController::class, '"'"'rotate'"'"'])->name('"'"'screensavers.rotate'"'"');\
' routes/web.php
fi

chown www-data:www-data app/Http/Controllers/Admin/ScreensaverController.php resources/views/admin/screensavers/index.blade.php routes/web.php
