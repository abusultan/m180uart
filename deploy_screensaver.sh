#!/bin/bash
cd /var/www/cutter

# 1. Create Model and Migration
php artisan make:model Screensaver -m

# Find the migration file
MIGRATION_FILE=$(ls database/migrations/*_create_screensavers_table.php | tail -n 1)

# Write the migration content
cat << 'EOF' > $MIGRATION_FILE
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::create('screensavers', function (Blueprint $table) {
            $table->id();
            $table->string('image_path');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('screensavers');
    }
};
EOF

# 2. Write the Model
cat << 'EOF' > app/Models/Screensaver.php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Screensaver extends Model
{
    protected $fillable = ['image_path', 'is_active'];

    public function getImageUrlAttribute()
    {
        return asset('storage/' . $this->image_path);
    }
}
EOF

# 3. Create the Controller
mkdir -p app/Http/Controllers/Api

cat << 'EOF' > app/Http/Controllers/Api/ScreensaverController.php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Screensaver;

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
}
EOF

# 4. Append the Route
grep -q "ScreensaverController" routes/api.php || cat << 'EOF' >> routes/api.php

use App\Http\Controllers\Api\ScreensaverController;
Route::get('/screensavers', [ScreensaverController::class, 'index']);
EOF

# 5. Run the migration
php artisan migrate --force

# 6. Ensure permissions are correct
chown -R www-data:www-data app/Models/Screensaver.php app/Http/Controllers/Api/ScreensaverController.php $MIGRATION_FILE routes/api.php
