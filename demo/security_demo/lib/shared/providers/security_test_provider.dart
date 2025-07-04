import 'package:engine_security/engine_security.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detector_test_result.dart';

class SecurityTestNotifier extends StateNotifier<Map<String, DetectorTestResult?>> {
  SecurityTestNotifier() : super({});

  Future<void> runDetectorTest(String detectorName) async {
    final stopwatch = Stopwatch()..start();

    state = {
      ...state,
      detectorName: DetectorTestResult(
        detectorName: detectorName,
        result: EngineSecurityCheckModel.secure(details: 'Preparando teste...'),
        timestamp: DateTime.now(),
        executionTime: Duration.zero,
        isRunning: true,
      ),
    };

    try {
      // Solicitar permissões de localização para GPS Fake
      if (detectorName == 'GPS Fake') {
        final permissionGranted = await _requestLocationPermissions();
        if (!permissionGranted) {
          stopwatch.stop();
          state = {
            ...state,
            detectorName: DetectorTestResult(
              detectorName: detectorName,
              result: EngineSecurityCheckModel.secure(
                details:
                    'Permissão de localização necessária. Vá em Configurações > Apps > Security Demo > Permissões e habilite Localização.',
                confidence: 0.0,
              ),
              timestamp: DateTime.now(),
              executionTime: stopwatch.elapsed,
              isRunning: false,
            ),
          };
          return;
        }

        // Aguardar um pouco para as permissões serem processadas
        await Future.delayed(const Duration(milliseconds: 500));
      }

      late IEngineSecurityDetector detector;

      switch (detectorName) {
        case 'Frida':
          detector = EngineFridaDetector(enabled: true);
          break;
        case 'Root/Jailbreak':
          detector = EngineRootDetector(enabled: true);
          break;
        case 'Emulator':
          detector = EngineEmulatorDetector(enabled: true);
          break;
        case 'Debugger':
          detector = EngineDebuggerDetector(enabled: true);
          break;
        case 'GPS Fake':
          detector = EngineGpsFakeDetector(enabled: true);
          break;
        case 'HTTPS Pinning':
          // Configurar certificados com pins válidos para demonstração
          final examplePins = [
            EngineCertificatePinModel(
              hostname: 'stmr.tech',
              pins: [
                '17a8d38a1f559246194bccae62a794ff80d419e849fa78811a4910d7283c1f75', // SHA-256 fingerprint real da STMR
                'a1b2c3d4e5f67890123456789012345678901234567890123456789012345678', // Pin de backup válido (64 chars hex)
              ],
              includeSubdomains: true,
              enforcePinning: true,
            ),
            EngineCertificatePinModel(
              hostname: 'google.com',
              pins: [
                'f3c2b1a098765432109876543210987654321098765432109876543210987654', // Pin primário (64 chars hex)
                'e4d3c2b109876543210987654321098765432109876543210987654321098765', // Pin de backup (64 chars hex)
              ],
              includeSubdomains: true,
              enforcePinning: true,
            ),
          ];

          detector = EngineHttpsPinningDetector(
            enabled: true,
            pinnedCertificates: examplePins,
            testConnectivity: false, // Desabilitar teste de conectividade no demo
            strictMode: false,
          );
          break;
        default:
          throw Exception('Detector não encontrado: $detectorName');
      }

      if (!detector.isAvailable) {
        throw Exception('Detector não disponível nesta plataforma');
      }

      final result = await detector.performCheck();
      stopwatch.stop();

      state = {
        ...state,
        detectorName: DetectorTestResult(
          detectorName: detectorName,
          result: result,
          timestamp: DateTime.now(),
          executionTime: stopwatch.elapsed,
          isRunning: false,
        ),
      };
    } catch (e) {
      stopwatch.stop();

      state = {
        ...state,
        detectorName: DetectorTestResult(
          detectorName: detectorName,
          result: EngineSecurityCheckModel.secure(details: 'Erro no teste: $e', confidence: 0.0),
          timestamp: DateTime.now(),
          executionTime: stopwatch.elapsed,
          isRunning: false,
        ),
      };
    }
  }

  Future<void> runAllTests() async {
    final detectors = ['Frida', 'Root/Jailbreak', 'HTTPS Pinning', 'GPS Fake', 'Emulator', 'Debugger'];

    for (final detector in detectors) {
      await runDetectorTest(detector);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  void clearResults() {
    state = {};
  }

  DetectorTestResult? getResult(String detectorName) {
    return state[detectorName];
  }

  /// Solicita permissões de localização necessárias para o teste de GPS Fake
  Future<bool> _requestLocationPermissions() async {
    try {
      // Verificar se as permissões já foram concedidas
      final locationStatus = await Permission.location.status;

      if (locationStatus == PermissionStatus.granted) {
        return true;
      }

      // Solicitar permissão de localização
      final result = await Permission.location.request();

      if (result == PermissionStatus.granted) {
        return true;
      }

      // Se a permissão foi negada permanentemente, informar o usuário
      if (result == PermissionStatus.permanentlyDenied) {
        return false;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}

final securityTestProvider = StateNotifierProvider<SecurityTestNotifier, Map<String, DetectorTestResult?>>((ref) {
  return SecurityTestNotifier();
});

final securitySummaryProvider = Provider<SecuritySummary>((ref) {
  final tests = ref.watch(securityTestProvider);

  int totalTests = tests.length;
  int completedTests = tests.values.where((test) => test != null && !test.isRunning).length;
  int threatsDetected = tests.values.where((test) => test != null && !test.isRunning && !test.result.isSecure).length;
  int secureTests = tests.values.where((test) => test != null && !test.isRunning && test.result.isSecure).length;

  return SecuritySummary(
    totalTests: totalTests,
    completedTests: completedTests,
    threatsDetected: threatsDetected,
    secureTests: secureTests,
    isRunning: tests.values.any((test) => test?.isRunning == true),
  );
});

class SecuritySummary {
  final int totalTests;
  final int completedTests;
  final int threatsDetected;
  final int secureTests;
  final bool isRunning;

  const SecuritySummary({
    required this.totalTests,
    required this.completedTests,
    required this.threatsDetected,
    required this.secureTests,
    required this.isRunning,
  });

  double get completionPercentage => totalTests > 0 ? (completedTests / totalTests) * 100 : 0.0;

  String get overallStatus {
    if (isRunning) return 'Executando testes...';
    if (completedTests == 0) return 'Nenhum teste executado';
    if (threatsDetected > 0) return 'Ameaças detectadas!';
    return 'Sistema seguro';
  }
}
