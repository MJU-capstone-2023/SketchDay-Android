import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../../utils/authService.dart';
import 'create_diary_page.dart';

class UploadPhotoPage extends StatefulWidget {
  @override
  _WritePageState createState() => _WritePageState();
}

class _WritePageState extends State<UploadPhotoPage> {
  DateTime selectedDate = DateTime.now();
  String summary = '';
  final _authService = AuthService();
  List<XFile> images = []; // 선택된 이미지를 저장하는 리스트

  Future<void> showDeleteDialog(int index) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('경고'),
          content: const Text('삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('아니요'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('예'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        images.removeAt(index);
      });
    }
  }

  Widget buildImage(File image, int index) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5.0),
            child: Image.file(
              image,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: () => showDeleteDialog(index),
            child: const Icon(
              Icons.remove_circle,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  void showDatePickerDialog() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && pickedDate != selectedDate) {
      setState(() {
        selectedDate = pickedDate;
      });
    }
  }

  Future getImage() async {
    print("getImage");
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedImages = await picker.pickMultiImage();

    setState(() {
      images.addAll(pickedImages);
      if (images.length > 10) {
        images = images.sublist(0, 10); // 이미지가 10장이 넘지 않도록 제한
      }
    });
  }

  Future<void> uploadImages(List<XFile> images) async {
    // 이미지를 s3에 업로드
    List<String> imagePaths = images
        .map((image) => p.basename(File(image.path).path))
        .toList(); // 파일명 + 확장자 추출

    List<String> uploadUrls =
        await getUploadUrls(imagePaths); // 각 파일에 대한 presign url 요청

    for (int i = 0; i < images.length; i++) {
      // 이미지 업로드
      File imageFile = File(images[i].path);
      var stream =
          http.ByteStream(DelegatingStream.typed(imageFile.openRead()));
      var length = await imageFile.length();
      var uri = Uri.parse(uploadUrls[i]);
      print(uri);

      var request = http.MultipartRequest("PUT", uri);
      var multipartFile = http.MultipartFile('file', stream, length,
          filename: p.basename(imageFile.path));

      request.files.add(multipartFile);

      var response = await request.send();

      if (response.statusCode == 200) {
        print('S3 이미지 업로드 성공');
        getSummary(imagePaths);
      } else {
        Fluttertoast.showToast(msg: "이미지 업로드에 실패했습니다.");
        return;
      }
    }
  }

  Future<void> getSummary(List<String> imageUrls) async {
    final url = '${dotenv.env['BASE_URL']}/diary/create'; // TODO: url 변경 필요
    final accessToken = await _authService.readAccessToken() ?? '';
    final response = await _authService.post(
      url,
      accessToken,
      body: {
        'imageUrls': imageUrls // TODO: 서버 변수명에 맞게 수정
      },
    );

    final responseJson = jsonDecode(utf8.decode(response.bodyBytes));
    print(responseJson);

    if (response.statusCode == 200) {
      String summary = responseJson['summary']; // TODO: 서버 변수명에 맞게 수정
      Navigator.push(
        // 일기 요약 완료시 저장 페이지로 이동
        context,
        MaterialPageRoute(
          builder: (_) => CreateDiaryPage(
            date: selectedDate.toIso8601String().split('T')[0],
            content: summary,
          ),
        ),
      );
    } else {
      Fluttertoast.showToast(msg: "일기 요약에 실패했습니다.");
      throw Exception('일기 요약에 실패했습니다.');
    }
  }

  Future<List<String>> getUploadUrls(List<String> imagePaths) async {
    // presign url 요청
    print(imagePaths);
    final url = '${dotenv.env['BASE_URL']}/diary/getS3Url';
    final accessToken = await _authService.readAccessToken() ?? '';
    final response = await _authService
        .put(url, accessToken, body: {"imagePaths": imagePaths});

    if (response.statusCode == 200) {
      var data = json.decode(response.body);
      print(data);
      return List<String>.from(data['s3_urls']); // url 리스트를 반환
    } else {
      Fluttertoast.showToast(msg: "이미지 업로드 URL 통신에 실패했습니다.");
      throw Exception('이미지 업로드에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40.0, left: 10.0, right: 10.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.pop(context); // 이전 페이지로 돌아가기
                  },
                  icon: const Icon(Icons.close),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    if (images.isEmpty) {
                      Fluttertoast.showToast(
                        msg: "이미지를 한 장 이상 선택해주세요.",
                        toastLength: Toast.LENGTH_SHORT,
                        gravity: ToastGravity.CENTER,
                      );
                    } else {
                      uploadImages(images);
                    }
                  },
                  child: const Text(
                    '다음',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 10.0),
                Text(
                  '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일',
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showDatePickerDialog();
                  },
                  icon: const Icon(Icons.arrow_drop_down),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    // 날씨 다이얼로그 표시
                  },
                  icon: const Icon(Icons.wb_sunny),
                ),
                IconButton(
                  onPressed: () {
                    // 기분 다이얼로그 표시
                  },
                  icon: const Icon(Icons.emoji_emotions),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 20.0, horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                  height: 400,
                  child: images.isEmpty
                      ? Image.asset(
                          'assets/images/no_messenger_img.png',
                          fit: BoxFit.cover,
                        )
                      : GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          children: List.generate(images.length, (index) {
                            return buildImage(File(images[index].path), index);
                          }),
                        ),
                ),
              ),
              ElevatedButton(
                onPressed: getImage,
                child: const Text('이미지 선택'),
              ),
              Container(
                margin: const EdgeInsets.only(top: 10.0),
                child: const Text('최대 10장까지 업로드 할 수 있어요'),
              )
            ],
          )
        ],
      ),
    );
  }
}