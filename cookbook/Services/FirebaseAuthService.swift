//
//  FirebaseAuthService.swift
//  cookbook
//
//  The real AuthServicing adapter. This is the only file (besides the
//  sign-in UI's Apple/Google token acquisition) that touches FirebaseAuth
//  or GoogleSignIn types directly.
//

import FirebaseAuth
import Foundation

final class FirebaseAuthService: AuthServicing {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    var currentUserEmail: String? {
        Auth.auth().currentUser?.email
    }

    func signInWithEmail(email: String, password: String) async throws -> AuthResult {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return AuthResult(userID: result.user.uid, isNewAccount: result.additionalUserInfo?.isNewUser ?? false)
    }

    func signUpWithEmail(email: String, password: String) async throws -> AuthResult {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        return AuthResult(userID: result.user.uid, isNewAccount: true)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult {
        let credential = OAuthProvider.credential(providerID: .apple, idToken: idToken, rawNonce: rawNonce)
        let result = try await Auth.auth().signIn(with: credential)
        return AuthResult(userID: result.user.uid, isNewAccount: result.additionalUserInfo?.isNewUser ?? false)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult {
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let result = try await Auth.auth().signIn(with: credential)
        return AuthResult(userID: result.user.uid, isNewAccount: result.additionalUserInfo?.isNewUser ?? false)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthServiceError.notSignedIn
        }
        try await user.delete()
    }
}
