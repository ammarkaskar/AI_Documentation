import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const DocumentationAIApp());
}

class DocumentationAIApp extends StatelessWidget {
  const DocumentationAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Documentation AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1419),
        fontFamily: 'Inter',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;
  String _generatedDocumentation = '';

  // TODO: Add your FREE Google Gemini API key here
  // Get it from: https://makersuite.google.com/app/apikey
  static const String GEMINI_API_KEY =
      'AIzaSyBegwhsyLwUHywY4UQZsuPE5Rw4o-lgjQ0';
  static const String GEMINI_API_URL =
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent';

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(ChatMessage(
        text: 'Hello, User\nCreate documentation with AI',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userMessage = _messageController.text.trim();
    setState(() {
      _messages.add(ChatMessage(
        text: userMessage,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isProcessing = true;
    });

    _messageController.clear();
    _scrollToBottom();

    await _callGeminiAPI(userMessage);
  }

  Future<void> _callGeminiAPI(String prompt) async {
    try {
      // Enhanced prompt for better documentation generation
      final enhancedPrompt = '''
You are a technical documentation expert. Generate comprehensive, well-structured documentation for: $prompt

Please format the documentation with:
- Clear headings and sections
- Detailed explanations
- Code examples if applicable
- Best practices
- Common use cases

Keep it professional and thorough.
''';

      final response = await http.post(
        Uri.parse('$GEMINI_API_URL?key=$GEMINI_API_KEY'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': enhancedPrompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 2048,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check if response has candidates and content
        if (data['candidates'] != null &&
            data['candidates'].isNotEmpty &&
            data['candidates'][0]['content'] != null &&
            data['candidates'][0]['content']['parts'] != null &&
            data['candidates'][0]['content']['parts'].isNotEmpty) {
          final aiResponse =
              data['candidates'][0]['content']['parts'][0]['text'];

          setState(() {
            _generatedDocumentation = aiResponse;
            _messages.add(ChatMessage(
              text: aiResponse,
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isProcessing = false;
          });
        } else {
          throw Exception('Invalid response format from API');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            'API Error: ${response.statusCode} - ${errorData['error']['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text:
              "Sorry, there was an error processing your request: ${e.toString()}\n\nPlease check your API key and try again.",
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isProcessing = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionTile(
              icon: Icons.picture_as_pdf,
              title: 'Generate PDF',
              onTap: () {
                Navigator.pop(context);
                _generatePDF();
              },
            ),
            _ActionTile(
              icon: Icons.download,
              title: 'Save Local',
              onTap: () {
                Navigator.pop(context);
                _saveLocal();
              },
            ),
            _ActionTile(
              icon: Icons.share,
              title: 'Share',
              onTap: () {
                Navigator.pop(context);
                _share();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to split text into manageable chunks for PDF
  List<String> _splitTextIntoChunks(String text, int maxChunkLength) {
    List<String> chunks = [];
    List<String> paragraphs = text.split('\n\n');
    
    String currentChunk = '';
    
    for (String paragraph in paragraphs) {
      // If adding this paragraph would exceed the limit, save current chunk and start new one
      if (currentChunk.length + paragraph.length > maxChunkLength && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.trim());
        currentChunk = paragraph + '\n\n';
      } else {
        currentChunk += paragraph + '\n\n';
      }
    }
    
    // Add the last chunk if it's not empty
    if (currentChunk.trim().isNotEmpty) {
      chunks.add(currentChunk.trim());
    }
    
    // If we still have chunks that are too long, split them by sentences
    List<String> finalChunks = [];
    for (String chunk in chunks) {
      if (chunk.length <= maxChunkLength) {
        finalChunks.add(chunk);
      } else {
        // Split by sentences
        List<String> sentences = chunk.split('. ');
        String currentSentenceChunk = '';
        
        for (int i = 0; i < sentences.length; i++) {
          String sentence = sentences[i];
          if (i < sentences.length - 1) sentence += '. '; // Add period back except for last sentence
          
          if (currentSentenceChunk.length + sentence.length > maxChunkLength && currentSentenceChunk.isNotEmpty) {
            finalChunks.add(currentSentenceChunk.trim());
            currentSentenceChunk = sentence;
          } else {
            currentSentenceChunk += sentence;
          }
        }
        
        if (currentSentenceChunk.trim().isNotEmpty) {
          finalChunks.add(currentSentenceChunk.trim());
        }
      }
    }
    
    return finalChunks;
  }

  Future<void> _generatePDF() async {
    if (_generatedDocumentation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No documentation generated yet. Please create documentation first.'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating PDF...'),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );

    try {
      // Create PDF document
      final pdf = pw.Document();
      
      // Split the documentation into manageable chunks
      final textChunks = _splitTextIntoChunks(_generatedDocumentation, 3000);
      
      // Add page with documentation content
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            List<pw.Widget> widgets = [
              // Title
              pw.Header(
                level: 0,
                child: pw.Text(
                  'AI Generated Documentation',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Generated timestamp
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 20),
            ];
            
            // Add each text chunk as a separate widget
            for (int i = 0; i < textChunks.length; i++) {
              widgets.add(
                pw.Text(
                  textChunks[i],
                  style: const pw.TextStyle(
                    fontSize: 12,
                    lineSpacing: 1.5,
                  ),
                  textAlign: pw.TextAlign.justify,
                ),
              );
              
              // Add some spacing between chunks, but not after the last one
              if (i < textChunks.length - 1) {
                widgets.add(pw.SizedBox(height: 15));
              }
            }
            
            return widgets;
          },
        ),
      );

      // Show print/save dialog
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'AI_Documentation_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF generated successfully!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: ${e.toString()}'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  Future<void> _saveLocal() async {
    if (_generatedDocumentation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No documentation generated yet. Please create documentation first.'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving locally...'),
        backgroundColor: Color(0xFF2196F3),
      ),
    );

    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission denied'),
              backgroundColor: Color(0xFFF44336),
            ),
          );
          return;
        }
      }

      // Create PDF document
      final pdf = pw.Document();
      
      // Split the documentation into manageable chunks
      final textChunks = _splitTextIntoChunks(_generatedDocumentation, 3000);
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            List<pw.Widget> widgets = [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'AI Generated Documentation',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 20),
            ];
            
            // Add each text chunk as a separate widget
            for (int i = 0; i < textChunks.length; i++) {
              widgets.add(
                pw.Text(
                  textChunks[i],
                  style: const pw.TextStyle(
                    fontSize: 12,
                    lineSpacing: 1.5,
                  ),
                  textAlign: pw.TextAlign.justify,
                ),
              );
              
              // Add some spacing between chunks, but not after the last one
              if (i < textChunks.length - 1) {
                widgets.add(pw.SizedBox(height: 15));
              }
            }
            
            return widgets;
          },
        ),
      );

      // Get directory to save file
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        final fileName = 'AI_Documentation_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${directory.path}/$fileName');
        
        // Save PDF to file
        await file.writeAsBytes(await pdf.save());
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to: ${file.path}'),
            backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        throw Exception('Could not access storage directory');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving PDF: ${e.toString()}'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  Future<void> _share() async {
    if (_generatedDocumentation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No documentation generated yet. Please create documentation first.'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing to share...'),
        backgroundColor: Color(0xFF9C27B0),
      ),
    );

    try {
      // Create PDF document
      final pdf = pw.Document();
      
      // Split the documentation into manageable chunks
      final textChunks = _splitTextIntoChunks(_generatedDocumentation, 3000);
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            List<pw.Widget> widgets = [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'AI Generated Documentation',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 20),
            ];
            
            // Add each text chunk as a separate widget
            for (int i = 0; i < textChunks.length; i++) {
              widgets.add(
                pw.Text(
                  textChunks[i],
                  style: const pw.TextStyle(
                    fontSize: 12,
                    lineSpacing: 1.5,
                  ),
                  textAlign: pw.TextAlign.justify,
                ),
              );
              
              // Add some spacing between chunks, but not after the last one
              if (i < textChunks.length - 1) {
                widgets.add(pw.SizedBox(height: 15));
              }
            }
            
            return widgets;
          },
        ),
      );

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final fileName = 'AI_Documentation_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${directory.path}/$fileName');
      
      // Save PDF to temporary file
      await file.writeAsBytes(await pdf.save());
      
      // Share the PDF file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'AI Generated Documentation',
        subject: 'Documentation PDF',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF ready to share!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing PDF: ${e.toString()}'),
          backgroundColor: const Color(0xFFF44336),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1A1F2E),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.purple.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Documentation AI',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showActionSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _MessageBubble(
                  message: _messages[index],
                  onGeneratePDF: !_messages[index].isUser ? () => _generatePDF() : null,
                );
              },
            ),
          ),
          if (_isProcessing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.blue.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Processing with Gemini AI...',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () {},
            color: Colors.grey.shade400,
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1419),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.grey.shade800,
                ),
              ),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.purple.shade400],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onGeneratePDF;

  const _MessageBubble({
    required this.message,
    this.onGeneratePDF,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.purple.shade400],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child:
                  const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? const Color(0xFF2196F3)
                        : const Color(0xFF1A1F2E),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      if (onGeneratePDF != null && message.text.length > 50) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onGeneratePDF,
                            icon: const Icon(Icons.picture_as_pdf, size: 16),
                            label: const Text('Convert to PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.person, size: 20, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.blue.shade400),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
