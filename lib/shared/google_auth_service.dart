import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart'; // New Import
import 'package:shared_preferences/shared_preferences.dart'; // New Import

class GoogleAuthService {
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // Your existing Web Client ID setup
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? '581115815178-dc0ciq2ng5e1oigufqc6spv53r4nmt03.apps.googleusercontent.com' : null,
    );
    _initialized = true;
  }

  /// Runs the Google sign-in flow and signs into Firebase.
  /// Returns the signed-in user's email, or throws a readable String message.
  static Future<String> signIn() async {
    await _ensureInitialized();
    try {
      UserCredential userCredential;

      if (kIsWeb) {
        // --- THE WEB FIX ---
        // Bypasses the google_sign_in package and uses Firebase's built-in web popup
        final authProvider = GoogleAuthProvider();
        userCredential = await FirebaseAuth.instance.signInWithPopup(authProvider);
        
      } else {
        // --- THE MOBILE FLOW (Android/iOS) ---
        // Your existing standard logic
        final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        
        if (idToken == null) {
          throw 'Could not verify your Google account. Please try again.';
        }
        
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final User? user = userCredential.user;
      final email = user?.email;
      
      if (email == null) throw 'Google sign-in did not return an email address.';

      // ==========================================================
      // --- THE NEW SINGLE-SESSION LOGIC (STEP 1) STARTS HERE ---
      // ==========================================================
      if (user != null) {
        // 1. Create a ticket using the exact current time
        String newSessionTicket = DateTime.now().millisecondsSinceEpoch.toString();

        // 2. Save it locally to the phone
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('local_session_ticket', newSessionTicket);

        // 3. Upload it to their Firestore profile
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'session_ticket': newSessionTicket,
        }, SetOptions(merge: true));
      }
      // ==========================================================
      // --- THE NEW SINGLE-SESSION LOGIC (STEP 1) ENDS HERE ---
      // ==========================================================

      return email;

    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw 'Sign-in cancelled.';
      }
      throw 'Google sign-in failed. Please try again.';
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'Google sign-in failed. Please try again.';
    }
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
  }
}