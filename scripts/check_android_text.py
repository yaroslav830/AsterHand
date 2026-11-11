"""Compile the production text insertion policy and isolated hint/selection fixtures."""
import pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='asterhand-text-') as directory:
    subprocess.run(['javac','-encoding','UTF-8','-d',directory,str(ROOT/'android/app/src/main/java/com/pocketagent/InputTextPolicy.java'),str(ROOT/'android/tests/host/com/pocketagent/InputTextPolicyTest.java')],check=True)
    subprocess.run(['java','-cp',directory,'com.pocketagent.InputTextPolicyTest'],check=True)
