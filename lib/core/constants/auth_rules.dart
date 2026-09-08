/// Credential rules that the client enforces to give immediate feedback.
///
/// These MUST stay in step with the server, which is the real authority:
/// `lr-management/controllers/adminController.js` (create / edit a user) and
/// `lr-management/controllers/authController.js` (change / reset password).
/// A client minimum looser than the server's turns into a 400 the user cannot
/// act on; a stricter one blocks a password the server would have accepted.
library;

/// Shortest password the server accepts, in characters.
const int kMinPasswordLength = 6;
