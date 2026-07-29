<%@ Page Language="C#" %>
<!DOCTYPE html>
<html>
<head>
  <title>ThruntOps Internal Portal</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
    h1 { color: #333; }
    ul { list-style: none; padding: 0; }
    li { margin: 10px 0; }
    a { color: #0066cc; text-decoration: none; font-size: 16px; }
    a:hover { text-decoration: underline; }
    .notice { background: #fffbe6; border: 1px solid #f0c040; padding: 10px; margin-top: 20px; }
  </style>
</head>
<body>
  <h1>ThruntOps Internal Portal</h1>
  <p>Welcome to the ThruntOps employee portal. Please log in to access restricted resources.</p>
  <ul>
    <li><a href="Login.aspx">Employee Login</a></li>
    <li><a href="Upload.aspx">Document Upload</a></li>
    <li><a href="View.aspx">Document Viewer</a></li>
  </ul>
  <div class="notice">
    <strong>Notice:</strong> This portal is for internal use only.
    Access is logged and monitored.
  </div>
</body>
</html>
