import 'package:flutter/material.dart';

class SocialIconButton extends StatelessWidget {
  final String asset;
  final VoidCallback onTap;
  const SocialIconButton({required this.asset, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.deepPurple, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Center(
          child: Image.asset(asset, width: 32, height: 32),
        ),
      ),
    );
  }
}
