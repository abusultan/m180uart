import 'package:flutter/material.dart';

class AppStrings {
  // English Translations
  static const Map<String, String> en = {
    'app_name': 'Anticrash Cutter',
    'login_title': 'Login',
    'login_subtitle': 'Sign in to continue',
    'create_account': 'Create Account',
    'name': 'Name',
    'email': 'Email',
    'phone': 'Phone',
    'address': 'Address',
    'password': 'Password',
    'confirm_password': 'Confirm Password',
    'login_button': 'Login',
    'register_button': 'Register',
    'register_now': 'Don\'t have an account? Register',
    'already_have_account': 'Already have an account? Login',
    'error_name_length': 'Name must be at least 3 characters',
    'error_email_empty': 'Please enter an email',
    'error_email_invalid': 'Please enter a valid email',
    'error_phone_empty': 'Please enter a phone number',
    'error_address_empty': 'Please enter an address',
    'error_password_length': 'Password must be at least 8 characters',
    'error_password_match': 'Passwords do not match',
    'error_generic': 'An error occurred',
    'language': 'Language',
    'english': 'English',
    'arabic': 'Arabic',
    'logout_title': 'Logout',
    'logout_confirm': 'Are you sure you want to logout?',
    'cancel': 'Cancel',
    'profile': 'Profile',
    'remaining_pieces': 'Remaining Pieces',
    'guest': 'Guest',
    'logout': 'Logout',
    'home': 'Home',
    'categories': 'Categories',
    'remaining': 'Remaining',
    'connect_cutter': 'Connect Cutter',
    'no_categories': 'No Categories Found',
  };

  // Arabic Translations
  static const Map<String, String> ar = {
    'app_name': 'Anticrash Cutter',
    'login_title': 'تسجيل الدخول',
    'login_subtitle': 'سجل الدخول للمتابعة',
    'create_account': 'إنشاء حساب',
    'name': 'الاسم',
    'email': 'البريد الإلكتروني',
    'phone': 'رقم الهاتف',
    'address': 'العنوان',
    'password': 'كلمة المرور',
    'confirm_password': 'تأكيد كلمة المرور',
    'login_button': 'دخول',
    'register_button': 'تسجيل',
    'register_now': 'ليس لديك حساب؟ سجل الآن',
    'already_have_account': 'لديك حساب بالفعل؟ سجل الدخول',
    'error_name_length': 'الاسم يجب أن يكون 3 أحرف على الأقل',
    'error_email_empty': 'الرجاء إدخال البريد الإلكتروني',
    'error_email_invalid': 'البريد الإلكتروني غير صالح',
    'error_phone_empty': 'الرجاء إدخال رقم الهاتف',
    'error_address_empty': 'الرجاء إدخال العنوان',
    'error_password_length': 'كلمة المرور يجب أن تكون 8 أحرف على الأقل',
    'error_password_match': 'كلمات المرور غير متطابقة',
    'error_generic': 'حدث خطأ ما',
    'language': 'اللغة',
    'english': 'English',
    'arabic': 'العربية',
    'logout_title': 'تسجيل الخروج',
    'logout_confirm': 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
    'cancel': 'إلغاء',
    'profile': 'الملف الشخصي',
    'remaining_pieces': 'القطع المتبقية',
    'guest': 'زائر',
    'logout': 'خروج',
    'home': 'الرئيسية',
    'categories': 'التصنيفات',
    'remaining': 'المتبقي',
    'connect_cutter': 'اتصل بالقاطعة',
    'no_categories': 'لا يوجد تصنيفات',
  };

  // Helper to get string based on language code
  static String get(String key, String langCode) {
    if (langCode == 'ar') {
      return ar[key] ?? en[key] ?? key;
    }
    return en[key] ?? key;
  }

  // Easy access via context
  static String of(BuildContext context, String key) {
    final Locale locale = Localizations.localeOf(context);
    return get(key, locale.languageCode);
  }
}
