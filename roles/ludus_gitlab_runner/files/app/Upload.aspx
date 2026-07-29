<%@ Page Language="C#" %>
<script runat="server">
  protected void btnUpload_Click(object sender, EventArgs e)
  {
    if (fileUpload.HasFile)
    {
      // Vulnerable: no extension validation — any file type accepted, including .aspx
      string savePath = Server.MapPath("~/uploads/") + fileUpload.FileName;
      fileUpload.SaveAs(savePath);
      lblResult.ForeColor = System.Drawing.Color.Green;
      lblResult.Text = "Uploaded: <a href=\"uploads/" + fileUpload.FileName + "\">"
                     + fileUpload.FileName + "</a> ("
                     + fileUpload.PostedFile.ContentLength + " bytes)";
    }
    else
    {
      lblResult.ForeColor = System.Drawing.Color.Red;
      lblResult.Text = "No file selected.";
    }
  }
</script>
<!DOCTYPE html>
<html>
<head>
  <title>ThruntOps — Document Upload</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
    h2 { color: #333; }
    .form-row { margin: 10px 0; }
    .result { margin-top: 14px; font-weight: bold; }
    a { font-size: 13px; color: #666; }
  </style>
</head>
<body>
  <h2>Document Upload</h2>
  <p>Upload documents for internal review. Accepted formats: PDF, DOCX, XLSX, PNG.</p>
  <form runat="server" enctype="multipart/form-data">
    <div class="form-row">
      <asp:FileUpload ID="fileUpload" runat="server" />
    </div>
    <div class="form-row">
      <asp:Button ID="btnUpload" runat="server" Text="Upload" OnClick="btnUpload_Click" />
    </div>
    <div class="result">
      <asp:Label ID="lblResult" runat="server" />
    </div>
  </form>
  <p><a href="Default.aspx">← Back to portal</a></p>
</body>
</html>
