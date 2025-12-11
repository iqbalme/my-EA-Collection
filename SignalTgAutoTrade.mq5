//+------------------------------------------------------------------+
//| FileReaderEA.mq5                                                |
//| Simple EA to read a text file and print its contents to Experts  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"

input string fileName = "data.txt";            // If using relative, file placed in MQL5/Files
input bool useAbsolutePath = false;              // Set true to use `absolutePath`
input string absolutePath = "C:\\temp\\data.txt"; // Full absolute path when useAbsolutePath=true
input bool printLineNumbers = true;              // Print line numbers in log

//+------------------------------------------------------------------+
int OnInit()
{
   string path = "";

   if (useAbsolutePath)
      path = absolutePath;
   else
   {
      // Terminal data path + MQL5/Files
      string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
      path = dataPath + "\\MQL5\\Files\\" + fileName;
   }

   Print("FileReaderEA: attempting to open file: ", path);

   int fh = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if (fh == INVALID_HANDLE)
   {
      // As a fallback, try opening the simple filename (works when file placed directly in Files and path resolution differs)
      Print("FileReaderEA: primary open failed (", IntegerToString(GetLastError()), "). Trying fallback with filename: ", fileName);
      fh = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI);
      if (fh == INVALID_HANDLE)
      {
         Print("FileReaderEA: Failed to open file. Error: ", IntegerToString(GetLastError()));
         return INIT_FAILED;
      }
   }

   // Read entire file into a single JSON string
   string json = "";
   while (!FileIsEnding(fh))
   {
      string s = FileReadString(fh);
      json += s;
   }
   FileClose(fh);

   // Trim BOM if present
   if (StringLen(json) >= 1 && StringGetCharacter(json,0)==65279)
      json = StringSubstr(json,1);

   Print("SignalTgAutoTrade: raw JSON content: " + json);

   // Parse and log all key/value pairs (including nested 'parsed' object)
   ParseAndLogJSON(json);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
void OnTick()
{
}
//+------------------------------------------------------------------+
//| JSON parsing helpers                                             |
//+------------------------------------------------------------------+
void ParseAndLogJSON(string s)
{
   // Start extracting key/value pairs from top-level object
   ExtractPairs(s, "");
}

// Extract key/value pairs from a JSON object string `s` and log them.
// `prefix` is used for nested keys (e.g., parsed.action -> "parsed.action").
void ExtractPairs(string s, string prefix)
{
   int pos = 0;
   int len = StringLen(s);
   while (true)
   {
      // find next '"' that starts a key
      int q1 = StringFind(s, "\"", pos);
      if (q1 == -1) break;
      // find end quote
      int q2 = StringFind(s, "\"", q1+1);
      if (q2 == -1) break;
      string key = StringSubstr(s, q1+1, q2 - q1 - 1);

      // find colon after q2
      int colon = StringFind(s, ':', q2+1);
      if (colon == -1) break;

      // move to first non-space after colon
      int vpos = colon + 1;
      while (vpos < len)
      {
         uchar c = (uchar)StringGetCharacter(s, vpos);
         if (c == 32 || c == 9 || c == 10 || c == 13) vpos++; else break;
      }
      if (vpos >= len) break;

      string fullKey = (prefix == "") ? key : prefix + "." + key;

      // If value starts with '"' it's a string
      int ch = StringGetCharacter(s, vpos);
      if (ch == 34)
      {
         int vq = StringFind(s, "\"", vpos+1);
         if (vq == -1) break;
         string value = StringSubstr(s, vpos+1, vq - vpos - 1);
         PrintFormat("JSON: %s = %s", fullKey, value);
         pos = vq + 1;
         continue;
      }
      else if (ch == 123)
      {
         // find matching closing brace
         int start = vpos;
         int depth = 0;
         int k = start;
         for (; k < len; k++)
         {
            int cc = StringGetCharacter(s, k);
            if (cc == 123) depth++;
            else if (cc == 125)
            {
               depth--;
               if (depth == 0) break;
            }
         }
         if (k >= len) break;
         string inner = StringSubstr(s, start+1, k - start - 1);
         // recursively extract from inner object
         ExtractPairs(inner, fullKey);
         pos = k + 1;
         continue;
      }
      else
      {
         // number, boolean, null or unquoted value: read until comma or closing brace
         int k = vpos;
         while (k < len)
         {
            int cc = StringGetCharacter(s, k);
            if (cc == 44 || cc == 125 || cc == 10 || cc == 13) break;
            k++;
         }
         string raw = StringSubstr(s, vpos, k - vpos);
         // trim spaces
         string value = Trim(raw);
         PrintFormat("JSON: %s = %s", fullKey, value);
         pos = k + 1;
         continue;
      }
   }
}

// Trim whitespace (spaces, tabs, CR, LF) from both ends
string Trim(string t)
{
   int L = StringLen(t);
   int i = 0; int j = L - 1;
   while (i <= j && (uchar)StringGetCharacter(t, i) <= 32) i++;
   while (j >= i && (uchar)StringGetCharacter(t, j) <= 32) j--;
   if (i > j) return "";
   return StringSubstr(t, i, j - i + 1);
}

//+------------------------------------------------------------------+
