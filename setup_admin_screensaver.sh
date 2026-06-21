#!/bin/bash
cd /var/www/cutter

# 1. Create Controller
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
}
EOF

# 2. Create View
mkdir -p resources/views/admin/screensavers

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
                                    <td width="150">
                                        <img src="{{ $s->image_url }}" alt="" class="img-fluid rounded" style="max-height: 80px;">
                                    </td>
                                    <td>
                                        @if($s->is_active)
                                            <span class="badge bg-success text-white">مفعل</span>
                                        @else
                                            <span class="badge bg-danger text-white">معطل</span>
                                        @endif
                                    </td>
                                    <td>{{ $s->created_at->format('Y-m-d') }}</td>
                                    <td>
                                        <div class="btn-group">
                                            <form action="{{ route('admin.screensavers.toggle', $s) }}" method="POST">
                                                @csrf
                                                <button type="submit" class="btn btn-sm btn-{{ $s->is_active ? 'warning' : 'success' }} me-1">
                                                    {{ $s->is_active ? 'تعطيل' : 'تفعيل' }}
                                                </button>
                                            </form>
                                            <form action="{{ route('admin.screensavers.destroy', $s) }}" method="POST" onsubmit="return confirm('هل أنت متأكد من الحذف؟')">
                                                @csrf
                                                @method('DELETE')
                                                <button type="submit" class="btn btn-sm btn-danger">حذف</button>
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
if ! grep -q "screensavers.index" routes/web.php; then
cat << 'EOF' >> routes/web.php

Route::prefix('admin')->name('admin.')->middleware(['auth', 'role:admin'])->group(function () {
    Route::resource('screensavers', \App\Http\Controllers\Admin\ScreensaverController::class)->only(['index', 'store', 'destroy']);
    Route::post('screensavers/{screensaver}/toggle', [\App\Http\Controllers\Admin\ScreensaverController::class, 'toggle'])->name('screensavers.toggle');
});
EOF
fi

# 4. Add Sidebar Link
if ! grep -q "admin.screensavers.index" resources/views/admin/partials/sidebar.blade.php; then
sed -i '' -e '/<\/ul>/i\
    @role('"'"'admin'"'"')\
    <li>\
        <a href="{{ route('"'"'admin.screensavers.index'"'"') }}" class="{{ request()->routeIs('"'"'admin.screensavers.*'"'"') ? '"'"'active'"'"' : '"'"''"'"' }}">\
            <i class="fas fa-desktop"></i>\
            <span>شاشة التوقف</span>\
        </a>\
    </li>\
    @endrole\
' resources/views/admin/partials/sidebar.blade.php || sed -i '/<\/ul>/i \
    @role("admin")\
    <li>\
        <a href="{{ route("admin.screensavers.index") }}" class="{{ request()->routeIs("admin.screensavers.*") ? "active" : "" }}">\
            <i class="fas fa-desktop"></i>\
            <span>شاشة التوقف</span>\
        </a>\
    </li>\
    @endrole' resources/views/admin/partials/sidebar.blade.php
fi

chown -R www-data:www-data app/Http/Controllers/Admin/ScreensaverController.php resources/views/admin/screensavers routes/web.php resources/views/admin/partials/sidebar.blade.php
