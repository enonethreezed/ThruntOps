<%@ Page Language="C#" %>
<%@ Import Namespace="System.IO" %>
<script runat="server">
  protected void Page_Load(object sender, EventArgs e)
  {
    string file = Request.QueryString["file"];
    if (!string.IsNullOrEmpty(file))
    {
      // Vulnerable: no path sanitization — directory traversal via ../
      string basePath = Server.MapPath("~/documents/");
      string fullPath = basePath + file;
      try
      {
        string content = File.ReadAllText(fullPath);
        lblContent.Text = Server.HtmlEncode(content);
        lblFile.Text = "File: " + fullPath;
      }
      catch (Exception ex)
      {
        lblContent.Text = "Error reading file: " + ex.Message;
        lblFile.Text = "Attempted path: " + fullPath;
      }
    }
  }
</script>
<!DOCTYPE html>
<html>
<head>
  <title>ThruntOps — Document Viewer</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
    h2 { color: #333; }
    .filepath { font-size: 12px; color: #888; margin-bottom: 8px; }
    pre { background: #fff; border: 1px solid #ddd; padding: 14px; white-space: pre-wrap; word-break: break-all; }
    form { margin-bottom: 16px; }
    input[type=text] { width: 300px; padding: 4px; }
    a { font-size: 13px; color: #666; }
  </style>
</head>
<body>
  <h2>Document Viewer</h2>
  <form method="get">
    <label>Document name: </label>
    <input type="text" name="file" value="<%= Server.HtmlEncode(Request.QueryString["file"] ?? "") %>" placeholder="e.g. internal_report.txt" />
    <input type="submit" value="View" />
  </form>
  <div class="filepath"><asp:Label ID="lblFile" runat="server" /></div>
  <pre><asp:Label ID="lblContent" runat="server" /></pre>
  <p><a href="Default.aspx">← Back to portal</a></p>
</body>
</html>
