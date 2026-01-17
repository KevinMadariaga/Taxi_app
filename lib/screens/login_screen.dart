import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
	final VoidCallback? onFinish;
	const LoginScreen({Key? key, this.onFinish}) : super(key: key);

	@override
	State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
	final PageController _pageController = PageController();
	int _current = 0;

	final List<Map<String, dynamic>> _pages = [
		{
			'icon': Icons.local_taxi,
			'title': 'Encuentra taxi de manera rápida y segura',
			'subtitle': 'Solicita un taxi desde tu ubicación y llega rápido a tu destino.'
		},
		{
			'icon': Icons.verified_user,
			'title': 'Conductores verificados',
			'subtitle': 'Conductores confiables y verificados para mayor seguridad.'
		},
		{
			'icon': Icons.payment,
			'title': 'Selecciona tu método de pago',
			'subtitle': 'Elige tarjeta o efectivo de forma rápida y segura.'
		},
	];

	void _next() {
		if (_current < _pages.length - 1) {
			_pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
		} else {
			_finish();
		}
	}

	void _skip() => _finish();

	void _finish() {
		if (widget.onFinish != null) {
			widget.onFinish!();
			return;
		}
		Navigator.pushReplacement(
			context,
			MaterialPageRoute(builder: (_) => const HomeView()),
		);
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: AppColores.background,
			body: SafeArea(
				child: Column(
					children: [
						Expanded(
							child: PageView.builder(
								controller: _pageController,
								itemCount: _pages.length,
								onPageChanged: (i) => setState(() => _current = i),
								itemBuilder: (context, index) {
									final page = _pages[index];
									return Padding(
										padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
										child: Column(
											mainAxisAlignment: MainAxisAlignment.start,
											crossAxisAlignment: CrossAxisAlignment.center,
											children: [
												const SizedBox(height: 24),
												Container(
													height: 160,
													width: 160,
													decoration: BoxDecoration(
														color: AppColores.surface,
														shape: BoxShape.circle,
														boxShadow: [
															BoxShadow(
																color: AppColores.divider.withOpacity(0.6),
																blurRadius: 12,
																offset: const Offset(0, 6),
															)
														],
													),
													child: Icon(page['icon'], size: 88, color: AppColores.primary),
												),
												const SizedBox(height: 36),
												Text(
													page['title'],
													textAlign: TextAlign.center,
													style: TextStyle(
														fontSize: 24,
														fontWeight: FontWeight.bold,
														color: AppColores.textPrimary,
													),
												),
												const SizedBox(height: 12),
												Text(
													page['subtitle'],
													textAlign: TextAlign.center,
													style: TextStyle(
														fontSize: 16,
														color: AppColores.textSecondary,
													),
												),
											],
										),
									);
								},
							),
						),
						Padding(
							padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
							child: Column(
								children: [
									Row(
										mainAxisAlignment: MainAxisAlignment.center,
										children: List.generate(
											_pages.length,
											(i) => AnimatedContainer(
												duration: const Duration(milliseconds: 250),
												margin: const EdgeInsets.symmetric(horizontal: 6),
												height: 8,
												width: _current == i ? 28 : 8,
												decoration: BoxDecoration(
													color: _current == i ? AppColores.primary : AppColores.divider,
													borderRadius: BorderRadius.circular(8),
												),
											),
										),
									),
									const SizedBox(height: 18),
									Row(
										children: [
											Expanded(
												child: TextButton(
													onPressed: _skip,
													style: TextButton.styleFrom(
														foregroundColor: AppColores.textPrimary,
													),
													child: const Text('Saltar'),
												),
											),
											const SizedBox(width: 12),
											Expanded(
												flex: 2,
												child: ElevatedButton(
													onPressed: _next,
													style: ElevatedButton.styleFrom(
														backgroundColor: AppColores.buttonPrimary,
														foregroundColor: AppColores.textWhite,
														padding: const EdgeInsets.symmetric(vertical: 14),
														shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
													),
													child: Text(_current < _pages.length - 1 ? 'Siguiente' : 'Comenzar'),
												),
											),
										],
									),
								],
							),
						),
					],
				),
			),
		);
	}
}

