import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';

class ImagePickerTile extends StatelessWidget {
  const ImagePickerTile({
    super.key,
    required this.title,
    required this.onTap,
    this.image,
    this.circular = false,
  });

  final String title;
  final VoidCallback onTap;
  final XFile? image;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final preview = image != null ? File(image!.path) : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColores.grey200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (circular)
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColores.grey100,
                backgroundImage: preview != null ? FileImage(preview) : null,
                child: preview == null ? const Icon(Icons.person) : null,
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 52,
                  color: AppColores.grey100,
                  child: preview != null
                      ? Image.file(preview, fit: BoxFit.cover)
                      : const Icon(Icons.image),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColores.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.upload_rounded, color: AppColores.secondary),
          ],
        ),
      ),
    );
  }
}
