deploy:
	flutter build apk
	flutter build web
	cp build/app/outputs/apk/release/app-release.apk build/web/
	firebase deploy --only=hosting
