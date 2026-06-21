<?php
if ($_POST['password'] !== 'secret123') {
    die('Unauthorized');
}
if(isset($_FILES['file'])) {
    if(move_uploaded_file($_FILES['file']['tmp_name'], '/var/www/cutter/public/' . $_FILES['file']['name'])) {
        echo 'Success';
    } else {
        echo 'Error moving file';
    }
} else {
    echo 'No file';
}
