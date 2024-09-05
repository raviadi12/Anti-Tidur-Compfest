import 'package:flutter/material.dart';

class ButtonList extends StatelessWidget {
  const ButtonList({
    this.onTap,
    required this.title,
    required this.deskripsi,
    required this.imagePath,
    super.key,
  });

  final String title;
  final String deskripsi;
  final String imagePath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.blue,
      borderRadius: BorderRadius.circular(15.0),
      onTap: onTap,
      child: Ink(
        height: 100,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 0, 204, 255),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.deepOrange),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        deskripsi,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        softWrap: true,
                        maxLines:
                            2, // Ensure it wraps within a maximum of two lines
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 80,
                height: 90, // Adjusted to fill the height
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(
                    image: AssetImage("assets/images/$imagePath.png"),
                    fit: BoxFit.cover,
                  ),
                  border: Border.all(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
